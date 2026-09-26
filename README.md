# Proyecto final SQL con PostgreSQL

## Análisis comercial y logístico de Olist

Este proyecto analiza ventas, clientes, productos, costos de flete y cumplimiento de entregas en el e-commerce brasileño Olist. El objetivo es responder preguntas de negocio con PostgreSQL y dejar un proceso reproducible desde la carga de los CSV hasta la interpretación de los resultados.

El análisis muestra dos conclusiones principales. Los pedidos demorados tienen una calificación media mucho menor que los pedidos entregados a tiempo, y noviembre de 2017 fue el mes de mayor facturación del período analizado. Estos resultados orientan acciones de retención, planificación de capacidad y mejora logística.

## Preguntas de negocio

El archivo `analisis.sql` responde estas preguntas:

1. ¿Cuáles son los cinco clientes con mayor gasto total?
2. ¿Cómo evolucionaron las ventas mensuales y cuál fue la variación frente al mes anterior?
3. ¿Cuáles fueron los tres productos menos vendidos?
4. ¿Qué pedidos ocuparon los primeros puestos de facturación dentro de cada categoría?
5. ¿Qué categorías generan más facturación y qué peso tiene el flete en cada una?
6. ¿Cómo cambia la satisfacción cuando un pedido llega después de la fecha prometida?

## Dataset y modelo relacional

Se utilizaron siete archivos del conjunto Olist Brazilian E-Commerce Public Dataset:

| Tabla | Archivo CSV | Filas esperadas | Función |
| --- | --- | ---: | --- |
| `customers` | `olist_customers_dataset.csv` | 99.441 | Identifica clientes y ubicación |
| `products` | `olist_products_dataset.csv` | 32.951 | Describe productos y categorías |
| `sellers` | `olist_sellers_dataset.csv` | 3.095 | Identifica vendedores |
| `category_translation` | `product_category_name_translation.csv` | 71 | Traduce categorías al inglés |
| `orders` | `olist_orders_dataset.csv` | 99.441 | Registra estado y fechas del pedido |
| `order_items` | `olist_order_items_dataset.csv` | 112.650 | Registra productos, precios y flete |
| `order_reviews` | `olist_order_reviews_dataset.csv` | 99.224 | Registra calificaciones del cliente |

Relaciones principales:

```text
customers 1 ─── N orders 1 ─── N order_items N ─── 1 products
                         │                │
                         │                └──────── N ─── 1 sellers
                         │
                         └────── 1 ─── N order_reviews

products N ─── 0..1 category_translation
```

`customer_id` identifica la relación entre un pedido y su registro de cliente. Para el análisis de fidelidad se usa `customer_unique_id`, porque una misma persona puede aparecer con más de un `customer_id`.

## Preparación y limpieza

La limpieza se implementa en vistas para conservar intactas las tablas importadas:

- `vw_orders_clean` normaliza el estado del pedido y clasifica la entrega como `on_time`, `late`, `not_delivered` o `missing_delivery_date`.
- `vw_sales_detail` combina pedidos, clientes, ítems, productos y categorías. Usa `COALESCE` para proteger cálculos monetarios y para asignar `uncategorized` cuando falta la categoría.
- `vw_reviews_by_order` agrega las reseñas antes de unirlas con pedidos. Esto evita duplicar pedidos cuando existe más de una fila de reseña.
- La fecha real de entrega no se reemplaza. `COALESCE` genera un campo separado para reportes, de modo que una fecha estimada nunca se confunda con una entrega confirmada.
- Los indicadores comerciales consideran pedidos entregados y compras anteriores al 1 de septiembre de 2018. El corte evita interpretar meses incompletos como una caída real.
- La serie mensual comienza en enero de 2017 porque los meses de 2016 son parciales y tienen muy pocas operaciones.

Controles realizados sobre los CSV:

- No hay claves duplicadas en `orders`, `customers`, `products` ni en la clave compuesta de `order_items`.
- Hay 2.965 pedidos sin fecha real de entrega. Es un faltante esperado principalmente para pedidos no entregados.
- Hay 610 productos sin categoría; la vista los agrupa como `uncategorized`.
- `price` y `freight_value` no contienen nulos ni importes negativos en la fuente analizada.
- Hay 551 filas de reseña adicionales respecto de la cantidad de pedidos reseñados. Se agregan por pedido antes del análisis de satisfacción.

## Hallazgos principales

### Clientes de mayor valor

El cliente con mayor gasto acumulado es `0a0a92112bd4c708ca5fde585afaa872`, con R$ 13.664,08 distribuidos en ocho ítems de un pedido. El segundo cliente es `da122df9eeddfedc1dc1f5349a1a690c`, con R$ 7.571,63 en dos pedidos.

El resultado sugiere que el gasto alto no siempre representa fidelidad: cuatro de los cinco clientes con mayor gasto realizaron un solo pedido. Una estrategia de retención debería separar valor monetario de frecuencia de compra.

### Evolución mensual

Noviembre de 2017 fue el mes de mayor facturación, con R$ 1.153.364,20 y 7.289 pedidos entregados. La facturación, calculada como producto más flete, creció 53,55 % frente a octubre. Este salto merece revisión por campaña, estacionalidad y capacidad logística antes de usarlo como referencia para pronósticos.

Entre junio y agosto de 2018 la facturación se mantuvo alrededor de R$ 1 millón mensual. Agosto cerró en R$ 985.491,64, un descenso de 4,12 % frente a julio.

### Productos de baja rotación

Los tres productos menos vendidos registraron una unidad cada uno:

| Producto | Categoría | Ingreso del producto |
| --- | --- | ---: |
| `46fce52cef5caa7cc225a5531c946c8b` | health_beauty | R$ 2,20 |
| `310dc32058903b6416c71faff132df9e` | stationery | R$ 2,29 |
| `680cc8535be7cc69544238c1d6a83fe8` | pet_shop | R$ 2,90 |

Como muchos productos tienen una sola unidad vendida, la consulta desempata por ingreso y por identificador. La baja rotación debe evaluarse junto con antigüedad, disponibilidad y margen antes de retirar un producto.

### Categorías y flete

`health_beauty` lidera la facturación de productos con R$ 1.233.131,72. Le siguen `watches_gifts`, con R$ 1.166.176,98, y `bed_bath_table`, con R$ 1.023.434,76.

El costo logístico no pesa igual en todas las categorías. En `furniture_decor` representa 19,13 % del valor combinado de producto y flete, mientras que en `watches_gifts` representa 7,76 %. Conviene revisar tarifas, dimensiones y políticas de envío por categoría en lugar de aplicar una única regla comercial.

### Demora y satisfacción

Los pedidos demorados obtienen una calificación media de 2,57, frente a 4,29 en los pedidos entregados a tiempo. Además, 53,99 % de los pedidos demorados recibe una calificación de 1 o 2; entre los pedidos a tiempo, esa proporción es 9,19 %.

La asociación es fuerte, aunque el análisis no demuestra causalidad por sí solo. La prioridad operativa es detectar pedidos con riesgo de demora y comunicar el problema antes de la fecha prometida.

## Estructura del repositorio

```text
proyecto_final_sql_olist/
├── estructura.sql   # Tablas, restricciones, índices, vistas y carga
├── analisis.sql     # Calidad de datos y consultas de negocio
└── README.md        # Contexto, ejecución, resultados y conclusiones
```

## Cómo ejecutar el proyecto

### 1. Crear la base de datos

Desde una conexión a la base `postgres`, ejecutar una sola vez:

```sql
CREATE DATABASE capstone_project;
```

Después, abrir una nueva conexión a `capstone_project`. PostgreSQL no admite `USE nombre_base`.

### 2. Crear la estructura

Ejecutar `estructura.sql` completo. El script crea el esquema `capstone`, las siete tablas, claves primarias y foráneas, índices y vistas de limpieza.

El script comienza con `DROP SCHEMA IF EXISTS capstone CASCADE`. Esto permite repetir la carga durante el desarrollo, pero elimina las tablas existentes dentro de ese esquema.

### 3. Importar los CSV en pgAdmin

En cada tabla, elegir **Import/Export Data**, seleccionar **Import** y configurar:

- Format: `csv`
- Header: `Yes`
- Delimiter: `,`
- Encoding: `UTF8`

Importar en este orden para respetar las claves foráneas:

1. `customers`
2. `products`
3. `sellers`
4. `category_translation`
5. `orders`
6. `order_items`
7. `order_reviews`

Los nombres `product_name_length` y `product_description_length` corrigen el error ortográfico `lenght` de los encabezados originales. El orden de las columnas no cambia.

También se puede cargar con `\copy` desde `psql` si los CSV están en una carpeta `data` dentro del repositorio:

```sql
\copy capstone.customers FROM 'data/olist_customers_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\copy capstone.products FROM 'data/olist_products_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\copy capstone.sellers FROM 'data/olist_sellers_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\copy capstone.category_translation FROM 'data/product_category_name_translation.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\copy capstone.orders FROM 'data/olist_orders_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\copy capstone.order_items FROM 'data/olist_order_items_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\copy capstone.order_reviews FROM 'data/olist_order_reviews_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
```

`\copy` es un comando del cliente `psql`; no debe pegarse en el Query Tool de pgAdmin.

### 4. Verificar y analizar

Al terminar la importación, volver a ejecutar el control de conteos ubicado al final de `estructura.sql`. Si los totales coinciden con la tabla de este README, ejecutar `analisis.sql` completo o consulta por consulta.

## Técnicas de SQL aplicadas

- DDL con tipos de datos, `PRIMARY KEY`, claves compuestas, `FOREIGN KEY` y `CHECK`.
- Carga masiva desde CSV.
- Vistas para limpieza sin modificar la fuente.
- `COALESCE`, `NULLIF`, `TRIM` y `CASE` para tratar nulos y categorías.
- `INNER JOIN` y `LEFT JOIN` para combinar siete tablas.
- `GROUP BY`, `SUM`, `COUNT`, `AVG` y filtros con `FILTER`.
- CTE con `WITH` para dividir consultas complejas en pasos legibles.
- `DATE_TRUNC` para series mensuales.
- `LAG` y `RANK` como funciones de ventana.
- Índices sobre columnas utilizadas en filtros y relaciones.
- Controles de granularidad para detectar explosiones de filas en los JOIN.

## Criterios de aceptación cubiertos

- El repositorio contiene `estructura.sql`, `analisis.sql` y `README.md`.
- Las consultas combinan varias tablas mediante JOINs.
- Se incluyen agregaciones, `CASE`, `LAG` y `RANK`.
- La etapa de limpieza usa `COALESCE` y documenta el tratamiento de nulos.
- Los tipos `TIMESTAMP` y `NUMERIC` se utilizan para fechas e importes.
- Hay más de cinco preguntas de negocio comentadas.
- El README interpreta resultados y explica cómo reproducirlos.

## Limitaciones

- Los datos cubren 2016 a 2018 y no representan el estado actual del mercado.
- Una asociación entre demora y mala calificación no prueba causalidad; también pueden influir el producto, el vendedor o la atención recibida.
- El dataset no incluye costo de adquisición, margen ni inventario, por lo que no permite calcular rentabilidad completa.
- Los nombres de clientes y productos no están disponibles. Los análisis identifican entidades mediante códigos.
