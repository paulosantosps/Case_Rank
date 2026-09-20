ENTREGÁVEIS - RELATORIOS FINAIS

-- RELATÓRIO DAS INSTALAÇÕES
-- Registros das Instalações
-- Quais deles geraram pedido
-- Quais pedidos são válidos
-- Quais foram faturados

DROP TABLE IF EXISTS gold.relatorio_instalacoes;
CREATE TABLE gold.relatorio_instalacoes AS
SELECT
    i.pk_instalacao,
    u.user_id,
    i.install_time,
    u.platform,
    i.attributed_touch_time,
    COALESCE(i.site_id, c.site_id) AS site_id,
    u.country_code,
    i.validacao_data_atribuicao,
    -- 2) pedido
    CASE WHEN c.pk_conversao IS NOT NULL THEN 'Yes' ELSE 'No' END AS gerou_pedido,
    c.af_order_id,
    c.event_time             AS pedido_time,
    c.event_revenue          AS pedido_receita,
    c.event_revenue_currency AS pedido_moeda,
    -- Validação do pedido
    c.validate_event,
    NULLIF(CONCAT_WS(', ',
        CASE WHEN c.pk_conversao IS NOT NULL
              AND NOT COALESCE(c.is_primary_attribution, FALSE) THEN 'Atribuição não primária' END,
        CASE WHEN i.validacao_data_atribuicao = 'No' THEN 'Data de atribuição anterior a 08/05/2025' END,
        CASE WHEN c.validacao_time_zone       = 'No' THEN 'Fuso horário fora da janela' END,
        CASE WHEN c.validacao_axx             = 'No' THEN 'Pedido fora do padrão ABR' END,
        CASE WHEN c.validacao_geo             = 'No' THEN 'País divergente' END,
        CASE WHEN c.currency_validation       = 'No' THEN 'Moeda divergente' END,
        CASE WHEN c.validacao_article         = 'No' THEN 'Artigo inválido' END
    ), '') AS motivo_reprovacao,
    -- Faturamento
    c.faturada,
    c.crm_status,
    dp.data                  AS crm_data_pedido,
    c.crm_event_revenue      AS crm_receita,
    c.validate_client,
    -- situação final da linha
    c.categoria_conversao
FROM gold.ft_instalacao i
  LEFT JOIN gold.ft_conversao c 
    ON c.fk_instalacao = i.pk_instalacao
  LEFT JOIN gold.dim_usuario u             
    ON u.user_id = i.fk_user
  LEFT JOIN gold.dim_data dp          
    ON dp.sk_data = c.fk_data_pedido;



-- RELATÓRIO FINAL DE CONVERSÃO
-- Construção da Tabela Final de Conversão
-- Quais Eventos geraram Ordem de Pedido
-- Quais passaram nas Regras de Validações
-- Quais foram Faturados
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
