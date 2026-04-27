/* @bruin

name: marts.dim_city
type: pg.sql

description: |
  City dimension. Sentinel row (id=0, city='(Unknown)'). The parenthesised
  literal cannot be produced by the INITCAP cleaning in staging.cars, so it
  cannot collide with a real value.

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
      - name: unique

@bruin */

WITH distinct_vals AS (
    SELECT DISTINCT city
    FROM staging.cars
    WHERE city IS NOT NULL
      AND city <> '(Unknown)'
),
ranked AS (
    SELECT
        DENSE_RANK() OVER (ORDER BY city)::BIGINT AS city_id,
        city
    FROM distinct_vals
)
SELECT 0::BIGINT AS city_id, '(Unknown)' AS city
UNION ALL
SELECT city_id, city FROM ranked
