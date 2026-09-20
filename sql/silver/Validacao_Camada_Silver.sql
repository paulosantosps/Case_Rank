
-- Validação dos Registros
SELECT COUNT(*), COUNT(DISTINCT user_id) AS qtd_user_id
FROM silver.install;

SELECT COUNT(*), COUNT(DISTINCT order_id) AS qtd_order_id
FROM silver.faturadas
