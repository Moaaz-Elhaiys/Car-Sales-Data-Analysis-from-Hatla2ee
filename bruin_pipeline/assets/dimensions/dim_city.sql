/* @bruin

name: marts.dim_city
type: pg.sql

description: City dimension. Sentinel row (id=0, city='Unknown').

depends:
  - staging.cars

materialization:
  type: table

columns:
  - name: city_id
    type: bigint
    checks:
      - name: not_null
      - name: unique
  - name: city
    type: text
    checks:
      - name: not_null

@bruin */

WITH distinct_vals AS (
    SELECT DISTINCT city
    FROM staging.cars
    WHERE city IS NOT NULL
),
ranked AS (
    SELECT
        DENSE_RANK() OVER (ORDER BY city)::BIGINT AS city_id,
        city
    FROM distinct_vals
)
SELECT 0::BIGINT AS city_id, 'Unknown' AS city
UNION ALL
SELECT city_id, city FROM ranked
