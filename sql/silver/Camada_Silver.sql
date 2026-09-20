-- SCRIPT PARA GERAÇÃO DA CAMADA SILVER
-- Tratamento e Transformação dos Dados

-- Criação do Schema
CREATE SCHEMA IF NOT EXISTS silver;

-- Criacao da tabela silver para o evento de Instalação
DROP TABLE IF EXISTS silver.install;
CREATE TABLE silver.install AS
SELECT
    user_id,
    customer_user_id,
    CAST(attributed_touch_time AS TIMESTAMP)      AS attributed_touch_time,
    CAST(install_time AS TIMESTAMP)               AS install_time,
    CAST(install_time AS TIMESTAMP)               AS install_date,
    CAST(event_time AS TIMESTAMP)                 AS event_time,
    LOWER(TRIM(platform))                         AS platform,
    UPPER(TRIM(country_code))                     AS country_code,
    UPPER(TRIM(state))                            AS state,
    city,
    site_id,
    device_category,
    device_model,
    os_version,
    region, 
    UPPER(TRIM(operator))                         AS operator, 
    UPPER(TRIM(carrier))                          AS carrier, 
    language 
FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY user_id, install_time) AS aux
    FROM bronze.install_brz 
) 
WHERE aux = 1; -- Remove Duplicatas pelo User e Data de Instalação


-- Criacao da tabela silver para o Evento de Compras Faturadas
-- foi descartadas as linhas em duplicatas
DROP TABLE IF EXISTS silver.faturadas;
CREATE TABLE silver.faturadas AS
SELECT
    order_id,
    status,
    CAST(month AS DATE)                           AS mes_referencia,
    CAST(order_date AS DATE)                      AS order_date,
    UPPER(TRIM(ctry_delivery))                    AS ctry_delivery,
    demand_value_lcy,
    demand_value_eur,
    event_revenue,
    event_revenue_currency,
    event_revenue_eur,
    user_id
FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY order_id) AS aux
    FROM bronze.faturadas_brz
)
WHERE aux = 1;


-- Criacao da tabela silver para os eventos de Pedido
-- Origem das Querys de Validação
-- 19 pedidos aparecem mais de uma vez
DROP TABLE IF EXISTS silver.event_pedidos;
CREATE TABLE silver.event_pedidos AS
SELECT
    ROW_NUMBER() OVER (ORDER BY event_time, user_id, af_order_id) AS event_id,
    *,
    -- TL-66: Validate_Event
    CASE WHEN validacao_article         = 'No'
           OR validacao_axx             = 'No'
           OR currency_validation       = 'No'
           OR validacao_data_atribuicao = 'No'
           OR validacao_geo             = 'No'
           OR validacao_time_zone       = 'No'
           OR NOT COALESCE(is_primary_attribution, FALSE)
         THEN 'Not OK' ELSE 'OK' END AS validate_event,
    -- TL-65: Clean_Event
    CASE WHEN validacao_article = 'No'
           OR COALESCE(event_revenue_currency, '') <> 'BRL'
           OR COALESCE(af_currency, '')            <> 'BRL'
           OR COALESCE(country_code, '')           <> 'BR'
           OR COALESCE(profile_country, '')        <> 'BR'
           OR validacao_time_zone = 'No'
           OR validacao_axx       = 'No'
         THEN 'No' ELSE 'Yes' END AS clean_event,
    -- reenvios: 1 = primeira ocorrência do pedido, 2 ou mais = repetição
    CASE WHEN af_order_id IS NULL THEN 1
         ELSE ROW_NUMBER() OVER (PARTITION BY af_order_id ORDER BY event_time)
    END AS order_event_seq
FROM silver.event_regras;
