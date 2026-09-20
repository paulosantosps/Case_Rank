-- SCRIPT PARA GERAÇÃO DA CAMADA GOLD
-- Construção da Tabela Final de Conversão

-- Criação do Schema
CREATE SCHEMA IF NOT EXISTS gold;

-- Construção da Tabela Final de Conversão
DROP TABLE IF EXISTS gold.ft_conversao_final;
CREATE TABLE gold.conversao_final AS
SELECT
    e.event_id,
    e.af_order_id,
    e.user_id,
    e.customer_user_id,
    e.event_time,
    CAST(e.event_time AS DATE) AS event_date,
    e.platform,
    e.state,
    e.city,
    e.site_id,
    e.attributed_touch_time,
    e.install_time,
    e.is_primary_attribution,
    -- receita do evento (vinda do app)
    e.event_revenue,
    e.event_revenue_currency,
    e.event_revenue_eur,
    -- regras da silver
    e.validacao_data_atribuicao,
    e.validacao_axx,
    e.validacao_geo,
    e.currency_validation,
    e.validacao_article,
    e.validacao_time_zone,
    e.validate_event,
    e.clean_event,
    -- cruzamento com o CRM
    CASE WHEN f.order_id IS NOT NULL THEN 'Yes' ELSE 'No' END AS faturada,
    f.status            AS status_faturamento,
    f.event_revenue     AS receita_crm,
    f.event_revenue_eur AS receita_crm_eur,
    -- TL-64 + TL-63
    CASE WHEN e.validate_event <> 'OK'
           OR COALESCE(f.status, '') <> 'Approved'
           OR COALESCE(e.country_code, '') <> 'BR'
         THEN 'Not OK' ELSE 'OK' END AS validate_client,
    -- Evento Valido e Faturado ??? 
    CASE WHEN e.validate_event = 'OK'  AND f.order_id IS NOT NULL THEN 'Válida e faturada'
         WHEN e.validate_event = 'OK'  AND f.order_id IS NULL     THEN 'Válida e não faturada'
         WHEN e.validate_event <> 'OK' AND f.order_id IS NOT NULL THEN 'Inválida e faturada'
         ELSE 'Inválida e não faturada' END AS categoria_conversao
FROM silver.event_pedidos e
       LEFT JOIN silver.faturadas f
              ON f.order_id = e.af_order_id
WHERE e.order_event_seq = 1; -- Elimina os pedidos repetidos



-- Tabela com Atividade de Instalações dos Usuários
DROP TABLE IF EXISTS gold.ft_user_install;
CREATE TABLE gold.ft_user_install AS
SELECT
    i.user_id,
    i.install_time,
    i.install_date,
    i.attributed_touch_time,
    i.platform,
    i.state,
    i.city,
    i.site_id,
    i.device_category,
    i.device_model,
    i.os_version,
    COALESCE(c.qtd_compras, 0)           AS qtd_compras_mes,
    COALESCE(c.qtd_compras_validas, 0)   AS qtd_compras_validas_mes,
    COALESCE(c.qtd_compras_faturadas, 0) AS qtd_compras_faturadas_mes,
    CASE WHEN COALESCE(c.qtd_compras, 0) > 0 THEN 1 ELSE 0 END           AS comprou_no_mes,
    CASE WHEN COALESCE(c.qtd_compras_faturadas, 0) > 0 THEN 1 ELSE 0 END AS comprou_faturado_no_mes
FROM silver.install i
       LEFT JOIN (
              SELECT
                     user_id,
                     COUNT(*) AS qtd_compras,
                     SUM(CASE WHEN validate_event  = 'OK' THEN 1 ELSE 0 END) AS qtd_compras_validas,
                     SUM(CASE WHEN validate_client = 'OK' THEN 1 ELSE 0 END) AS qtd_compras_faturadas
              FROM gold.conversao_final
              GROUP BY user_id
       ) c 
       ON c.user_id = i.user_id;
