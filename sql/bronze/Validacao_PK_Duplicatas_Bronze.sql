
-- Verificando PK e Duplicidade na tabela INSTALL
SELECT 
    COUNT(*) AS linhas, 
    COUNT(DISTINCT user_id) AS usuarios,
    COUNT(DISTINCT site_id) AS sites
FROM bronze.install_brz;


-- Verificando PK e Duplicidade na tabela de FATURADAS
SELECT 
      COUNT(*) AS linhas,
      COUNT(DISTINCT order_id) AS pedidos, 
      COUNT(DISTINCT user_id)  AS usuarios
FROM bronze.faturadas_brz

SELECT order_id, COUNT(*) AS linhas
FROM bronze.faturadas_brz
GROUP by order_id
HAVING COUNT(*) > 1;

-- LINHAS EM DUPLICATA 
SELECT *
FROM bronze.faturadas_brz
WHERE order_id IN (
    SELECT order_id FROM bronze.faturadas_brz
    GROUP BY order_id HAVING COUNT(*) > 1
)
ORDER BY order_id;


-- Verificando PK e Duplicidade na tabela de EVENTOS
SELECT 
    COUNT(*) AS linhas, 
    COUNT(DISTINCT user_id) AS usuarios,
    COUNT(DISTINCT customer_user_id) AS clientes,
    COUNT(DISTINCT site_id) AS sites
FROM bronze.event_brz;

-- Buscar o ID na Coluna JSON
SELECT
    COUNT(*) AS linhas,
    COUNT(DISTINCT event_value::json ->> 'af_order_id')  AS af_order_id
FROM bronze.event_brz;

