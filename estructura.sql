/*
    PROYECTO FINAL SQL - ANALISIS DE E-COMMERCE OLIST
    Archivo: estructura.sql
    Motor: PostgreSQL

    Este script crea el esquema relacional, las restricciones, los indices
    y las vistas de limpieza. La base capstone_project debe crearse antes,
    porque PostgreSQL no permite cambiar de base de datos con USE.

    Orden de trabajo:
    1. Crear la base capstone_project y conectarse a ella.
    2. Ejecutar este archivo completo.
    3. Importar los CSV en el orden indicado al final del archivo.
    4. Ejecutar analisis.sql.
*/


-- =============================================================
-- 1. ESQUEMA DE TRABAJO
-- =============================================================

DROP SCHEMA IF EXISTS capstone CASCADE;
CREATE SCHEMA capstone;
SET search_path TO capstone, public;


-- =============================================================
-- 2. TABLAS MAESTRAS
-- Los codigos postales se guardan como texto para conservar ceros
-- a la izquierda. Los importes usan NUMERIC para evitar errores de
-- redondeo propios de los tipos de punto flotante.
-- =============================================================

CREATE TABLE customers (
    customer_id VARCHAR(32) PRIMARY KEY,
    customer_unique_id VARCHAR(32) NOT NULL,
    customer_zip_code_prefix VARCHAR(5),
    customer_city VARCHAR(100),
    customer_state CHAR(2)
);


CREATE TABLE products (
    product_id VARCHAR(32) PRIMARY KEY,
    product_category_name VARCHAR(100),
    product_name_length INTEGER,
    product_description_length INTEGER,
    product_photos_qty INTEGER,
    product_weight_g INTEGER,
    product_length_cm INTEGER,
    product_height_cm INTEGER,
    product_width_cm INTEGER,

    CONSTRAINT chk_products_weight
        CHECK (product_weight_g IS NULL OR product_weight_g >= 0),

    CONSTRAINT chk_products_dimensions
        CHECK (
            (product_length_cm IS NULL OR product_length_cm >= 0)
            AND (product_height_cm IS NULL OR product_height_cm >= 0)
            AND (product_width_cm IS NULL OR product_width_cm >= 0)
        )
);


CREATE TABLE sellers (
    seller_id VARCHAR(32) PRIMARY KEY,
    seller_zip_code_prefix VARCHAR(5),
    seller_city VARCHAR(100),
    seller_state CHAR(2)
);


CREATE TABLE category_translation (
    product_category_name VARCHAR(100) PRIMARY KEY,
    product_category_name_english VARCHAR(100) NOT NULL
);


-- =============================================================
-- 3. TABLAS TRANSACCIONALES
-- orders representa una fila por pedido. order_items puede tener
-- varias filas por pedido; por eso usa una clave primaria compuesta.
-- =============================================================

CREATE TABLE orders (
    order_id VARCHAR(32) PRIMARY KEY,
    customer_id VARCHAR(32) NOT NULL,
    order_status VARCHAR(20) NOT NULL,
    order_purchase_timestamp TIMESTAMP NOT NULL,
    order_approved_at TIMESTAMP,
    order_delivered_carrier_date TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,
    order_estimated_delivery_date TIMESTAMP NOT NULL,

    CONSTRAINT fk_orders_customers
        FOREIGN KEY (customer_id)
        REFERENCES customers (customer_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
);


CREATE TABLE order_items (
    order_id VARCHAR(32) NOT NULL,
    order_item_id INTEGER NOT NULL,
    product_id VARCHAR(32) NOT NULL,
    seller_id VARCHAR(32) NOT NULL,
    shipping_limit_date TIMESTAMP NOT NULL,
    price NUMERIC(12, 2),
    freight_value NUMERIC(12, 2),

    CONSTRAINT pk_order_items
        PRIMARY KEY (order_id, order_item_id),

    CONSTRAINT fk_order_items_orders
        FOREIGN KEY (order_id)
        REFERENCES orders (order_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    CONSTRAINT fk_order_items_products
        FOREIGN KEY (product_id)
        REFERENCES products (product_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    CONSTRAINT fk_order_items_sellers
        FOREIGN KEY (seller_id)
        REFERENCES sellers (seller_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    CONSTRAINT chk_order_items_price
        CHECK (price IS NULL OR price >= 0),

    CONSTRAINT chk_order_items_freight
        CHECK (freight_value IS NULL OR freight_value >= 0)
);


-- review_id se repite en el archivo fuente, pero la combinacion
-- review_id + order_id es unica. La clave compuesta conserva todas
-- las respuestas sin inventar un identificador nuevo.
CREATE TABLE order_reviews (
    review_id VARCHAR(32) NOT NULL,
    order_id VARCHAR(32) NOT NULL,
    review_score INTEGER NOT NULL,
    review_comment_title TEXT,
    review_comment_message TEXT,
    review_creation_date TIMESTAMP NOT NULL,
    review_answer_timestamp TIMESTAMP NOT NULL,

    CONSTRAINT pk_order_reviews
        PRIMARY KEY (review_id, order_id),

    CONSTRAINT fk_order_reviews_orders
        FOREIGN KEY (order_id)
        REFERENCES orders (order_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    CONSTRAINT chk_order_reviews_score
        CHECK (review_score BETWEEN 1 AND 5)
);


-- =============================================================
-- 4. INDICES
-- Se indexan columnas usadas en JOIN, filtros y agrupaciones. No se
-- crean indices sobre todas las columnas porque cada indice tambien
-- agrega costo a la carga y al mantenimiento de los datos.
-- =============================================================

CREATE INDEX idx_customers_unique_id
    ON customers (customer_unique_id);

CREATE INDEX idx_orders_customer_id
    ON orders (customer_id);

CREATE INDEX idx_orders_purchase_timestamp
    ON orders (order_purchase_timestamp);

CREATE INDEX idx_orders_status
    ON orders (order_status);

CREATE INDEX idx_order_items_product_id
    ON order_items (product_id);

CREATE INDEX idx_order_items_seller_id
    ON order_items (seller_id);

CREATE INDEX idx_products_category
    ON products (product_category_name);

CREATE INDEX idx_order_reviews_order_id
    ON order_reviews (order_id);


-- =============================================================
-- 5. VISTAS DE LIMPIEZA Y TRANSFORMACION
-- Las tablas originales se conservan sin sobrescribir datos. Las
-- reglas de limpieza quedan centralizadas en vistas reproducibles.
-- =============================================================

CREATE OR REPLACE VIEW vw_orders_clean AS
SELECT
    o.order_id,
    o.customer_id,
    LOWER(TRIM(o.order_status)) AS order_status,
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,

    -- Se conserva la fecha real como NULL cuando no existe. La fecha
    -- estimada solo completa un campo separado para reportes.
    COALESCE(
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date
    ) AS delivery_date_for_reporting,

    CASE
        WHEN LOWER(TRIM(o.order_status)) <> 'delivered' THEN 'not_delivered'
        WHEN o.order_delivered_customer_date IS NULL THEN 'missing_delivery_date'
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 'late'
        ELSE 'on_time'
    END AS delivery_status
FROM orders AS o;


CREATE OR REPLACE VIEW vw_reviews_by_order AS
SELECT
    r.order_id,
    COUNT(*) AS review_rows,
    ROUND(AVG(r.review_score), 2) AS review_score,
    MIN(r.review_creation_date) AS first_review_date,
    MAX(r.review_answer_timestamp) AS last_answer_timestamp
FROM order_reviews AS r
GROUP BY r.order_id;


CREATE OR REPLACE VIEW vw_sales_detail AS
SELECT
    oi.order_id,
    oi.order_item_id,
    oc.customer_id,
    c.customer_unique_id,
    NULLIF(TRIM(c.customer_state), '') AS customer_state,
    oi.product_id,
    oi.seller_id,

    COALESCE(
        NULLIF(TRIM(ct.product_category_name_english), ''),
        NULLIF(TRIM(p.product_category_name), ''),
        'uncategorized'
    ) AS product_category,

    oc.order_status,
    oc.order_purchase_timestamp,
    oc.order_delivered_customer_date,
    oc.order_estimated_delivery_date,
    oc.delivery_status,

    -- COALESCE evita que un importe faltante convierta toda la suma
    -- de la fila en NULL. Los datos fuente no contienen nulos en estas
    -- columnas, pero la regla protege futuras cargas.
    COALESCE(oi.price, 0.00)::NUMERIC(12, 2) AS price,
    COALESCE(oi.freight_value, 0.00)::NUMERIC(12, 2) AS freight_value,
    (
        COALESCE(oi.price, 0.00)
        + COALESCE(oi.freight_value, 0.00)
    )::NUMERIC(12, 2) AS item_total
FROM order_items AS oi
INNER JOIN vw_orders_clean AS oc
    ON oc.order_id = oi.order_id
INNER JOIN customers AS c
    ON c.customer_id = oc.customer_id
LEFT JOIN products AS p
    ON p.product_id = oi.product_id
LEFT JOIN category_translation AS ct
    ON ct.product_category_name = p.product_category_name;


-- =============================================================
-- 6. INSTRUCCIONES DE CARGA
-- En pgAdmin, usar Import/Export Data sobre cada tabla, seleccionar
-- formato CSV, Header = Yes, delimitador coma y codificacion UTF8.
-- Respetar este orden para no violar las claves foraneas:
--
-- 1. customers            <- olist_customers_dataset.csv
-- 2. products             <- olist_products_dataset.csv
-- 3. sellers              <- olist_sellers_dataset.csv
-- 4. category_translation <- product_category_name_translation.csv
-- 5. orders               <- olist_orders_dataset.csv
-- 6. order_items          <- olist_order_items_dataset.csv
-- 7. order_reviews        <- olist_order_reviews_dataset.csv
--
-- Los nombres corregidos product_name_length y
-- product_description_length ocupan la misma posicion que las
-- columnas "lenght" del CSV original; la importacion es posicional.
-- =============================================================


-- =============================================================
-- 7. CONTROL RAPIDO POSTERIOR A LA CARGA
-- Estos conteos esperados permiten detectar una importacion parcial.
-- =============================================================

SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL
SELECT 'products', COUNT(*) FROM products
UNION ALL
SELECT 'sellers', COUNT(*) FROM sellers
UNION ALL
SELECT 'category_translation', COUNT(*) FROM category_translation
UNION ALL
SELECT 'orders', COUNT(*) FROM orders
UNION ALL
SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL
SELECT 'order_reviews', COUNT(*) FROM order_reviews
ORDER BY table_name;
