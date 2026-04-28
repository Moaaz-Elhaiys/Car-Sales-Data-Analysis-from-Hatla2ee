/* @bruin

name: marts.dim_origin_country
type: pg.sql

description: |
  Origin-country dimension (where the model originates). Often sparse on
  used-car listings -- those rows route to the sentinel id=0. The
  parenthesised '(Unknown)' literal cannot be produced by the INITCAP
  cleaning in staging.cars, so it cannot collide with a real value.

depends:
  - staging.cars

materialization:
  type: table

columns:
  - name: origin_country_id
    type: bigint
    checks:
      - name: not_null
      - name: unique
  - name: origin_country
    type: text
    checks:
      - name: not_null
      - name: unique

@bruin */

WITH distinct_vals AS (
    SELECT DISTINCT origin_country
    FROM staging.cars
    WHERE origin_country IS NOT NULL
      AND origin_country <> '(Unknown)'
),
ranked AS (
    SELECT
        DENSE_RANK() OVER (ORDER BY origin_country)::BIGINT AS origin_country_id,
        origin_country
    FROM distinct_vals
)
SELECT 0::BIGINT AS origin_country_id, '(Unknown)' AS origin_country
UNION ALL
SELECT origin_country_id, origin_country FROM ranked
