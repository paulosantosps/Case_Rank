--ANÁLISE DAS TABELAS DO SCHEMA DA CAMADA BRONZE

-- Validando número de registros
SELECT count(*)
FROM bronze.install_brz

-- Analise dos colunas e Tipagem
SELECT *
FROM bronze.event_brz
LIMIT 5

-- Identificação de Coluna tipo JSON
SELECT event_value
FROM bronze.event_brz
LIMIT 5

SELECT
    event_value::json ->> 'af_order_id' AS af_order_id,
    event_value::json ->> 'time::local' AS time_local
FROM bronze.event_brz
LIMIT 5

-- Testar JOIN 
SELECT count(*) AS eventos_encontrados_no_crm
FROM bronze.event_brz
LEFT JOIN bronze.faturadas_brz
  ON faturadas_brz.order_id = event_brz.event_value::json ->> 'af_order_id'
