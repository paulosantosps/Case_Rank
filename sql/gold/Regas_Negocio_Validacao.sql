
-- Criando Tabela Temporária para analisar as Regas de Validação
DROP TABLE IF EXISTS silver.event_json;
CREATE TABLE silver.event_json AS
SELECT
    CAST(attributed_touch_time AS TIMESTAMP)            AS attributed_touch_time,
    CAST(install_time::TIMESTAMP AS TIMESTAMP)          AS install_time,
    CAST(event_time::TIMESTAMP AS TIMESTAMP)            AS event_time,
    event_name,
    event_value,
    event_revenue,
    event_revenue_currency,
    event_revenue_eur,
    site_id,
    UPPER(TRIM(country_code))                           AS country_code,
    state,
    city,
    language,
    user_id,
    customer_user_id,
    device_category,
    LOWER(TRIM(platform))                              AS platform,
    is_primary_attribution,
    device_model,
    -- campos extraídos do JSON
    event_value::JSON ->> 'af_order_id'                AS af_order_id,
    event_value::JSON ->> 'af_currency'                AS af_currency,
    event_value::JSON ->> 'event::country'             AS event_country,
    event_value::JSON ->> 'profile::countryselected'   AS profile_country,
    (event_value::JSON ->> 'time::local')::TIMESTAMP   AS time_local
FROM bronze.event_brz;


-- TL-74	Validacao_Data_Atribuicao
-- "Se country_code = 'BR', se o 'attributed_touch_time' for antes de 08/05/2025, o resultado será 'No'. 
-- Caso o 'attributed_touch_time' estiver vazio, fazer as mesmas comparações, mas com o 'install_time'."

SELECT
    CASE WHEN country_code = 'BR'
              AND COALESCE(attributed_touch_time, install_time) < TIMESTAMP '2025-05-08 00:00:00'
         THEN 'No' 
         ELSE 'Yes' 
         END AS validacao_data_atribuicao,
    COUNT(*)
FROM silver.event_json
GROUP BY 1;


-- TL-73	Validacao_AXX
-- "Após o 'event_value' ser quebrado, irá gerar uma coluna chamada 'af_order_id', o comparativo será a partir dela. 
-- Se o 'country_code'='BR', o af_order_id tem que começar com 'ABR', caso contrário, não é válido (No)"

SELECT
    CASE WHEN country_code = 'BR'
              AND COALESCE(af_order_id, '') NOT LIKE 'ABR%'
         THEN 'No' 
         ELSE 'Yes' 
         END AS validacao_axx,
    COUNT(*)
FROM silver.event_json
GROUP BY 1;


-- TL-72	Validacao_Geo
-- "Se 'country_code' for algo diferente de BR, não é Válido (No). 
-- 'country_code', 'event::country', 'profile::countryselected' todos devem ser iguais, se não forem não é válido = 'No'. 
-- Caso contrário 'Yes'"

SELECT
    CASE WHEN country_code = 'BR'
              AND country_code = UPPER(TRIM(event_country))
              AND country_code = UPPER(TRIM(profile_country))
         THEN 'Yes' 
         ELSE 'No' 
         END AS validacao_geo,
    COUNT(*)
FROM silver.event_json
GROUP BY 1;


-- TL-71	expected_currency  +  TL-70	Currency_validation 
-- Se 'country_code'= 'BR', o resultado deverá ser 'BRL'.
-- "Se 'expected currency' estiver vazio, então 'No'. 
-- 'expected_currency'  deve ser igual a 'event_revenue_currency' e a 'af_currency', nesse caso 'Yes', caso contrário 'No'."

SELECT
    expected_currency,
    CASE WHEN expected_currency IS NULL 
          THEN 'No'
         WHEN expected_currency = event_revenue_currency AND expected_currency = af_currency 
          THEN 'Yes'
         ELSE 'No' END AS currency_validation,
    COUNT(*)
FROM (
    SELECT *,
           CASE WHEN country_code = 'BR' 
            THEN 'BRL' 
          END AS expected_currency
    FROM silver.event_json
) 
GROUP BY 1, 2;


-- TL-69	Validacao_Article
-- "Se no event value contém 'purchasecle' então 'No', 
--caso contrário 'Yes'."

SELECT
    CASE WHEN LOWER(event_value) LIKE '%purchasecle%'
          THEN 'No' 
          ELSE 'Yes' 
    END AS validacao_article,
    COUNT(*)
FROM silver.event_json
GROUP BY 1;


-- TL-68	Time_Zone_Difference
-- A diferença entre o tempo do evento 'event_time' e o tempo Extraído do event_value( time::local )

SELECT
    ROUND(((EXTRACT(EPOCH FROM event_time) - EXTRACT(EPOCH FROM time_local)) / 60.0)::NUMERIC, 0) AS diff_min,
    COUNT(*)
FROM silver.event_json
GROUP BY 1
ORDER BY 2 DESC;


-- TL-67	Validacao_Time_Zone
-- "O campo 'event_value' não está vazio ({}).
-- O campo 'event_value' contém a chave 'time::local'.
-- O 'country_code' é 'BR'.
-- O valor de 'time_zone_difference' está dentro da janela de duração: Entre 02:59:00 e 07:01:00
-- Se todas as condições são verdadeiras, retornar ""Yes"", 
-- Caso contrário ""No""."

SELECT
    CASE WHEN TRIM(event_value) <> '{}'
              AND time_local IS NOT NULL
              AND country_code = 'BR'
              AND diff_min BETWEEN 179 AND 421
         THEN 'Yes' 
         ELSE 'No' 
    END AS validacao_time_zone,
    COUNT(*)
FROM (
    SELECT *,
           (EXTRACT(EPOCH FROM event_time) - EXTRACT(EPOCH FROM time_local)) / 60.0 AS diff_min
    FROM silver.event_json
) 
GROUP BY 1;



-- Criação das Tabelas Unificadas das Regras para demais Validações
DROP TABLE IF EXISTS silver.event_regras;
CREATE TABLE silver.event_regras AS
WITH CTE_regras_consolidadas AS (
    SELECT
         *,
        -- TL-74
        CASE WHEN country_code = 'BR'
                  AND COALESCE(attributed_touch_time, install_time) < TIMESTAMP '2025-05-08 00:00:00'
             THEN 'No' ELSE 'Yes' END AS validacao_data_atribuicao,
        -- TL-73
        CASE WHEN country_code = 'BR'
                  AND COALESCE(af_order_id, '') NOT LIKE 'ABR%'
             THEN 'No' ELSE 'Yes' END AS validacao_axx,
        -- TL-72
        CASE WHEN country_code = 'BR'
                  AND country_code = UPPER(TRIM(event_country))
                  AND country_code = UPPER(TRIM(profile_country))
             THEN 'Yes' ELSE 'No' END AS validacao_geo,
        -- TL-71
        CASE WHEN country_code = 'BR' 
              THEN 'BRL' END AS expected_currency,
        -- TL-69
        CASE WHEN LOWER(event_value) LIKE '%purchasecle%'
             THEN 'No' ELSE 'Yes' END AS validacao_article,
        -- TL-68 (diferença em minutos)
        (EXTRACT(EPOCH FROM event_time) - EXTRACT(EPOCH FROM time_local)) / 60.0
            AS time_zone_difference_min
    FROM silver.event_json
)
SELECT
    *,
    -- TL-70
    CASE WHEN expected_currency IS NULL THEN 'No'
         WHEN expected_currency = event_revenue_currency
              AND expected_currency = af_currency THEN 'Yes'
         ELSE 'No' END AS currency_validation,
    -- TL-67
    CASE WHEN TRIM(event_value) <> '{}'
              AND time_local IS NOT NULL
              AND country_code = 'BR'
              AND time_zone_difference_min BETWEEN 179 AND 421
         THEN 'Yes' ELSE 'No' END AS validacao_time_zone
FROM CTE_regras_consolidadas;


-- TL-66	Validate_Event + TL-65	Clean_Event

DROP TABLE IF EXISTS silver.event_regras2;
CREATE TABLE silver.event_regras2 AS
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

-- TL-64	validate_client + TL-63	Validate Client
-- Criados na Camada GOLD
