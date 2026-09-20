-- SCRIPT PARA GERAÇÃO DA CAMADA GOLD
-- Definição da Modelagem (Tabelas Fatos e Dimensões / Chaves Primárias e Estrangeiras)

-- Criação do Schema
CREATE SCHEMA IF NOT EXISTS gold;

-----------------------------------------------------------------------------------------------------------------------------------
-- Tabela Dimensão para Usuarios (uma linha por user_id)
DROP TABLE IF EXISTS gold.dim_usuario;
CREATE TABLE gold.dim_usuario AS
WITH CTE_Pedidos AS (
    -- uma linha por USUÁRIO (a compra mais recente), e não uma por pedido
    SELECT user_id, customer_user_id, platform, region, country_code
    FROM (
        SELECT
            user_id, customer_user_id, platform, region, country_code,
            ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY event_time DESC) AS aux
        FROM silver.event_pedidos
    ) 
    WHERE aux = 1
),
usuarios AS (
    SELECT user_id FROM silver.install
    UNION
    SELECT user_id FROM silver.event_pedidos
)
SELECT
    u.user_id,
    COALESCE(e.customer_user_id, i.customer_user_id) AS customer_user_id,
    COALESCE(i.platform, e.platform)                 AS platform,
    i.os_version,
    i.operator,
    i.carrier,
    COALESCE(i.region, e.region)                     AS region,
    COALESCE(i.country_code, e.country_code)         AS country_code,
    CASE WHEN i.user_id IS NOT NULL THEN 'Yes' ELSE 'No' END AS instalou_no_periodo
FROM usuarios u
    LEFT JOIN silver.install i
        ON i.user_id = u.user_id
    LEFT JOIN CTE_Pedidos e
        ON e.user_id = u.user_id;


-----------------------------------------------------------------------------------------------------------------------------------
-- Tabela Data para Analises em BI
DROP TABLE IF EXISTS gold.dim_data;
CREATE TABLE gold.dim_data AS
SELECT
    (EXTRACT(YEAR FROM d) * 10000 + EXTRACT(MONTH FROM d) * 100 + EXTRACT(DAY FROM d))::INT AS sk_data,
    d::DATE                      AS data,
    EXTRACT(YEAR FROM d)::INT    AS ano,
    EXTRACT(QUARTER FROM d)::INT AS trimestre,
    EXTRACT(MONTH FROM d)::INT   AS mes,
    SPLIT_PART('Janeiro,Fevereiro,Março,Abril,Maio,Junho,Julho,Agosto,Setembro,Outubro,Novembro,Dezembro',
               ',', EXTRACT(MONTH FROM d)::INT) AS nome_mes,
    EXTRACT(DAY FROM d)::INT     AS dia,
    EXTRACT(WEEK FROM d)::INT    AS semana_iso,
    EXTRACT(ISODOW FROM d)::INT  AS dia_semana,
    SPLIT_PART('Segunda,Terça,Quarta,Quinta,Sexta,Sábado,Domingo',
               ',', EXTRACT(ISODOW FROM d)::INT) AS nome_dia,
    CASE WHEN EXTRACT(ISODOW FROM d) IN (6, 7) THEN 'Yes' ELSE 'No' END AS fim_de_semana
FROM GENERATE_SERIES(DATE '2026-01-01', DATE '2026-12-31', INTERVAL '1 day') AS t(d);

-----------------------------------------------------------------------------------------------------------------------------------
-- Tabela Fato com Evento de Instalações dos Usuários (uma linha por instalação)
DROP TABLE IF EXISTS gold.ft_instalacao;
CREATE TABLE gold.ft_instalacao AS
SELECT
    u.user_id || i.install_time     AS pk_instalacao,
    u.user_id                       AS fk_user,
    i.site_id,
    d.sk_data                       AS fk_data_instalacao,
    i.attributed_touch_time,
    i.install_time,
    i.event_time,
    i.state,
    i.city,
    i.language,
    i.device_category,
    i.device_model,
    -- TL-74 
    CASE WHEN COALESCE(i.country_code, '') = 'BR'
          AND COALESCE(i.attributed_touch_time, i.install_time) < TIMESTAMP '2025-05-08 00:00:00'
         THEN 'No' ELSE 'Yes' END   AS validacao_data_atribuicao
FROM silver.install i
    LEFT JOIN gold.dim_usuario u
        ON u.user_id = i.user_id
    LEFT JOIN gold.dim_data d
        ON d.data = CAST(i.install_time AS DATE);

-----------------------------------------------------------------------------------------------------------------------------------
-- Tabela Fato com Evento de Pedido e Faturamento dos Usuários (uma linha por pedido)
DROP TABLE IF EXISTS gold.ft_conversao;
CREATE TABLE gold.ft_conversao AS
SELECT
    e.event_id                 AS pk_conversao,
    i.pk_instalacao            AS fk_instalacao,   -- vazio quando o usuário instalou antes do período
    u.user_id                  AS fk_user,
    e.site_id,
    de.sk_data                 AS fk_data_evento,
    dp.sk_data                 AS fk_data_pedido,
    e.af_order_id,
    e.event_name,
    e.event_value,
    e.attributed_touch_time,
    e.install_time,
    e.event_time,
    e.time_local,
    e.state,
    e.city,
    e.language,
    e.device_category,
    e.device_model,
    e.is_primary_attribution,
    e.event_revenue,
    e.event_revenue_currency,
    e.event_revenue_eur,
    -- regras TL-74 a TL-65
    e.validacao_data_atribuicao,
    e.validacao_axx,
    e.validacao_geo,
    e.expected_currency,
    e.currency_validation,
    e.validacao_article,
    e.time_zone_difference_min,
    e.validacao_time_zone,
    e.validate_event,
    e.clean_event,
    -- FATURADAS CRM
    CASE WHEN f.order_id IS NOT NULL THEN 'Yes' ELSE 'No' END AS faturada,
    f.status                  AS crm_status,
    f.mes_referencia          AS crm_mes_referencia,
    f.ctry_delivery           AS crm_ctry_delivery,
    f.demand_value_lcy        AS crm_demand_value_lcy,
    f.demand_value_eur        AS crm_demand_value_eur,
    f.event_revenue           AS crm_event_revenue,
    f.event_revenue_currency  AS crm_event_revenue_currency,
    f.event_revenue_eur       AS crm_event_revenue_eur,
    -- TL-64 + TL-63
    CASE WHEN e.validate_event <> 'OK'
           OR COALESCE(f.status, '') <> 'Approved'
           OR COALESCE(e.country_code, '') <> 'BR'
         THEN 'Not OK' ELSE 'OK' END AS validate_client,
    CASE WHEN e.validate_event = 'OK'  AND f.order_id IS NOT NULL THEN 'Válida e faturada'
         WHEN e.validate_event = 'OK'  AND f.order_id IS NULL     THEN 'Válida e não faturada'
         WHEN e.validate_event <> 'OK' AND f.order_id IS NOT NULL THEN 'Inválida e faturada'
         ELSE 'Inválida e não faturada' END AS categoria_conversao
FROM silver.event_pedidos e
    LEFT JOIN gold.dim_usuario u
        ON u.user_id = e.user_id
    LEFT JOIN gold.ft_instalacao i
        ON i.fk_user = e.user_id
    LEFT JOIN silver.faturadas f
        ON f.order_id = e.af_order_id
    LEFT JOIN gold.dim_data de
        ON de.data = CAST(e.event_time AS DATE)
    LEFT JOIN gold.dim_data dp
        ON dp.data = f.order_date
WHERE e.order_event_seq = 1;   -- elimina os pedidos repetidos (reenvios)
