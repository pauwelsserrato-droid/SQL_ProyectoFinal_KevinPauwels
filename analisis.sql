/*
    PROYECTO FINAL SQL - ANALISIS DE E-COMMERCE OLIST
    Archivo: analisis.sql
    Motor: PostgreSQL

    Alcance temporal de los indicadores comerciales:
    - pedidos entregados;
    - compras realizadas antes del 1 de septiembre de 2018.

    La serie mensual comienza el 1 de enero de 2017 porque los meses
    de 2016 son parciales y tienen muy pocas operaciones.

    El corte evita interpretar los meses incompletos del final del
    dataset como una caida real de ventas.
*/

SET search_path TO capstone, public;


-- =============================================================
-- 0. PERFIL Y CALIDAD DE LOS DATOS
-- Antes de analizar el negocio se revisan volumen, nulos y claves.
-- Esta etapa evita que faltantes o duplicados distorsionen resultados.
-- =============================================================

SELECT
    COUNT(*) AS total_orders,
    COUNT(*) FILTER (
        WHERE order_delivered_customer_date IS NULL
    ) AS missing_actual_delivery_date,
    COUNT(*) FILTER (
        WHERE order_estimated_delivery_date IS NULL
    ) AS missing_estimated_delivery_date,
    COUNT(*) FILTER (
        WHERE order_purchase_timestamp IS NULL
    ) AS missing_purchase_timestamp
FROM orders;


SELECT
    COUNT(*) AS total_order_items,
    COUNT(*) FILTER (WHERE price IS NULL) AS missing_price,
    COUNT(*) FILTER (WHERE freight_value IS NULL) AS missing_freight,
    COUNT(*) FILTER (WHERE price < 0) AS negative_price,
    COUNT(*) FILTER (WHERE freight_value < 0) AS negative_freight
FROM order_items;


SELECT
    COUNT(*) AS total_products,
    COUNT(*) FILTER (
        WHERE product_category_name IS NULL
           OR TRIM(product_category_name) = ''
    ) AS missing_category
FROM products;


SELECT
    COUNT(*) - COUNT(DISTINCT order_id) AS duplicate_order_ids
FROM orders;


SELECT
    COUNT(*) - COUNT(DISTINCT (order_id, order_item_id))
        AS duplicate_order_item_keys
FROM order_items;


-- Un pedido puede recibir mas de una fila de reseña. Se controla la
-- multiplicidad y luego se usa vw_reviews_by_order para no duplicar
-- pedidos en el analisis de satisfaccion.
SELECT
    COUNT(*) AS review_rows,
    COUNT(DISTINCT order_id) AS reviewed_orders,
    COUNT(*) - COUNT(DISTINCT order_id) AS additional_review_rows
FROM order_reviews;


-- =============================================================
-- 1. TOP 5 CLIENTES POR GASTO TOTAL
-- Problema de negocio: identificar clientes de alto valor para una
-- estrategia de retencion. customer_unique_id agrupa compras de la
-- misma persona aunque el dataset asigne distintos customer_id.
-- =============================================================

SELECT
    sd.customer_unique_id,
    COUNT(DISTINCT sd.order_id) AS delivered_orders,
    COUNT(*) AS purchased_items,
    ROUND(SUM(sd.price), 2) AS product_value,
    ROUND(SUM(sd.freight_value), 2) AS freight_value,
    ROUND(SUM(sd.item_total), 2) AS total_spend
FROM vw_sales_detail AS sd
WHERE sd.order_status = 'delivered'
  AND sd.order_purchase_timestamp < TIMESTAMP '2018-09-01 00:00:00'
GROUP BY sd.customer_unique_id
ORDER BY
    total_spend DESC,
    delivered_orders DESC,
    sd.customer_unique_id
LIMIT 5;


-- =============================================================
-- 2. VENTAS TOTALES POR MES Y VARIACION MENSUAL
-- Problema de negocio: detectar crecimiento, estacionalidad y meses
-- que requieren investigar capacidad operativa o demanda. LAG compara
-- cada mes con el anterior sin perder la fila del mes actual.
-- =============================================================

WITH monthly_sales AS (
    SELECT
        DATE_TRUNC('month', sd.order_purchase_timestamp)::DATE
            AS sales_month,
        COUNT(DISTINCT sd.order_id) AS delivered_orders,
        COUNT(*) AS sold_items,
        SUM(sd.price) AS product_value,
        SUM(sd.freight_value) AS freight_value,
        SUM(sd.item_total) AS total_sales
    FROM vw_sales_detail AS sd
    WHERE sd.order_status = 'delivered'
      AND sd.order_purchase_timestamp >= TIMESTAMP '2017-01-01 00:00:00'
      AND sd.order_purchase_timestamp < TIMESTAMP '2018-09-01 00:00:00'
    GROUP BY DATE_TRUNC('month', sd.order_purchase_timestamp)
),
monthly_comparison AS (
    SELECT
        ms.*,
        LAG(ms.sales_month) OVER (
            ORDER BY ms.sales_month
        ) AS previous_sales_month,
        LAG(ms.total_sales) OVER (
            ORDER BY ms.sales_month
        ) AS previous_month_sales
    FROM monthly_sales AS ms
)
SELECT
    mc.sales_month,
    mc.delivered_orders,
    mc.sold_items,
    ROUND(mc.product_value, 2) AS product_value,
    ROUND(mc.freight_value, 2) AS freight_value,
    ROUND(mc.total_sales, 2) AS total_sales,
    CASE
        -- Si falta un mes en la fuente, no se compara contra un periodo
        -- no consecutivo porque produciria una variacion enganosa.
        WHEN mc.sales_month = (
            mc.previous_sales_month + INTERVAL '1 month'
        )::DATE
        THEN ROUND(
            100.0
            * (mc.total_sales - mc.previous_month_sales)
            / NULLIF(mc.previous_month_sales, 0),
            2
        )
    END AS month_over_month_pct
FROM monthly_comparison AS mc
ORDER BY mc.sales_month;


-- =============================================================
-- 3. TRES PRODUCTOS MENOS VENDIDOS
-- Problema de negocio: localizar productos de muy baja rotacion para
-- revisar surtido, visibilidad o continuidad. Se usa un orden de
-- desempate determinista porque muchos productos vendieron una unidad.
-- =============================================================

SELECT
    sd.product_id,
    sd.product_category,
    COUNT(*) AS units_sold,
    COUNT(DISTINCT sd.order_id) AS delivered_orders,
    ROUND(SUM(sd.price), 2) AS product_revenue
FROM vw_sales_detail AS sd
WHERE sd.order_status = 'delivered'
  AND sd.order_purchase_timestamp < TIMESTAMP '2018-09-01 00:00:00'
GROUP BY
    sd.product_id,
    sd.product_category
ORDER BY
    units_sold ASC,
    product_revenue ASC,
    sd.product_id
LIMIT 3;


-- =============================================================
-- 4. RANKING DE PEDIDOS POR CATEGORIA
-- Problema de negocio: reconocer las compras de mayor valor dentro de
-- cada categoria. Primero se agrega el importe por pedido y categoria;
-- despues RANK crea un ranking independiente con PARTITION BY.
-- RANK conserva empates, por lo que una categoria puede devolver mas
-- de tres filas si varias compras comparten la tercera posicion.
-- =============================================================

WITH order_category_sales AS (
    SELECT
        sd.product_category,
        sd.order_id,
        COUNT(*) AS purchased_items,
        SUM(sd.item_total) AS order_category_total
    FROM vw_sales_detail AS sd
    WHERE sd.order_status = 'delivered'
      AND sd.order_purchase_timestamp < TIMESTAMP '2018-09-01 00:00:00'
    GROUP BY
        sd.product_category,
        sd.order_id
),
ranked_orders AS (
    SELECT
        ocs.*,
        RANK() OVER (
            PARTITION BY ocs.product_category
            ORDER BY ocs.order_category_total DESC
        ) AS category_rank
    FROM order_category_sales AS ocs
)
SELECT
    ro.product_category,
    ro.category_rank,
    ro.order_id,
    ro.purchased_items,
    ROUND(ro.order_category_total, 2) AS order_category_total
FROM ranked_orders AS ro
WHERE ro.category_rank <= 3
ORDER BY
    ro.product_category,
    ro.category_rank,
    ro.order_id;


-- =============================================================
-- 5. DESEMPENO COMERCIAL POR CATEGORIA
-- Problema de negocio: comparar facturacion y peso del flete. CASE
-- transforma la participacion del transporte en segmentos que ayudan
-- a priorizar revisiones de tarifa y logistica.
-- =============================================================

WITH category_sales AS (
    SELECT
        sd.product_category,
        COUNT(DISTINCT sd.order_id) AS delivered_orders,
        COUNT(*) AS units_sold,
        SUM(sd.price) AS product_value,
        SUM(sd.freight_value) AS freight_value,
        SUM(sd.item_total) AS total_sales
    FROM vw_sales_detail AS sd
    WHERE sd.order_status = 'delivered'
      AND sd.order_purchase_timestamp < TIMESTAMP '2018-09-01 00:00:00'
    GROUP BY sd.product_category
)
SELECT
    cs.product_category,
    cs.delivered_orders,
    cs.units_sold,
    ROUND(cs.product_value, 2) AS product_value,
    ROUND(cs.freight_value, 2) AS freight_value,
    ROUND(
        100.0 * cs.freight_value / NULLIF(cs.total_sales, 0),
        2
    ) AS freight_share_pct,
    CASE
        WHEN cs.freight_value / NULLIF(cs.total_sales, 0) >= 0.20
            THEN 'high_freight_share'
        WHEN cs.freight_value / NULLIF(cs.total_sales, 0) >= 0.10
            THEN 'medium_freight_share'
        ELSE 'low_freight_share'
    END AS freight_segment
FROM category_sales AS cs
ORDER BY
    product_value DESC,
    cs.product_category;


-- =============================================================
-- 6. DEMORA Y SATISFACCION DEL CLIENTE
-- Problema de negocio: medir si el incumplimiento de la fecha prometida
-- coincide con una peor experiencia. Solo se comparan pedidos entregados
-- con fechas validas. La vista de reseñas reduce primero a una fila por
-- pedido para evitar una explosion de filas en el JOIN.
-- =============================================================

SELECT
    oc.delivery_status,
    COUNT(*) AS reviewed_orders,
    ROUND(AVG(rbo.review_score), 2) AS average_review_score,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE rbo.review_score <= 2
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS low_review_pct
FROM vw_orders_clean AS oc
INNER JOIN vw_reviews_by_order AS rbo
    ON rbo.order_id = oc.order_id
WHERE oc.order_status = 'delivered'
  AND oc.order_purchase_timestamp < TIMESTAMP '2018-09-01 00:00:00'
  AND oc.order_delivered_customer_date IS NOT NULL
  AND oc.order_estimated_delivery_date IS NOT NULL
GROUP BY oc.delivery_status
ORDER BY oc.delivery_status;


-- =============================================================
-- 7. CONTROL DE GRANULARIDAD DESPUES DE LOS JOINS
-- Este control hace visible la diferencia entre pedidos e items. El
-- total de filas del detalle debe coincidir con los items que tienen
-- pedido y cliente validos, no con la cantidad de pedidos.
-- =============================================================

SELECT
    COUNT(*) AS sales_detail_rows,
    COUNT(DISTINCT order_id) AS distinct_orders,
    COUNT(DISTINCT customer_unique_id) AS distinct_customers,
    COUNT(DISTINCT product_id) AS distinct_products
FROM vw_sales_detail;
