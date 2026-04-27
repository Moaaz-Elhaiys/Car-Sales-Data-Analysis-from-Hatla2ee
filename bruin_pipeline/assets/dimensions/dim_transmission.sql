/* @bruin

name: marts.dim_transmission
type: pg.sql

description: |
  Transmission dimension. Sentinel row (id=0, transmission='(Unknown)'). The
  parenthesised literal cannot be produced by the INITCAP cleaning in
  staging.cars, so it cannot collide with a real value.

depends:
  - staging.cars

materialization:
  type: table

columns:
  - name: transmission_id
    type: bigint
    checks:
      - name: not_null
      - name: unique
  - name: transmission
    type: text
    checks:
      - name: not_null
      - name: unique

@bruin */

WITH distinct_vals AS (
    SELECT DISTINCT transmission
    FROM staging.cars
    WHERE transmission IS NOT NULL
      AND transmission <> '(Unknown)'
),
ranked AS (
    SELECT
        DENSE_RANK() OVER (ORDER BY transmission)::BIGINT AS transmission_id,
        transmission
    FROM distinct_vals
)
SELECT 0::BIGINT AS transmission_id, '(Unknown)' AS transmission
UNION ALL
SELECT transmission_id, transmission FROM ranked
