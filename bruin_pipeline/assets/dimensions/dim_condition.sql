/* @bruin

name: marts.dim_condition
type: pg.sql

description: |
  Condition dimension (typically "New" / "Used"). Sentinel row
  (id=0, condition='(Unknown)'). The parenthesised literal cannot be
  produced by the INITCAP cleaning in staging.cars, so it cannot collide
  with a real value.

depends:
  - staging.cars

materialization:
  type: table

columns:
  - name: condition_id
    type: bigint
    checks:
      - name: not_null
      - name: unique
  - name: condition
    type: text
    checks:
      - name: not_null
      - name: unique

@bruin */

WITH distinct_vals AS (
    SELECT DISTINCT condition
    FROM staging.cars
    WHERE condition IS NOT NULL
      AND condition <> '(Unknown)'
),
ranked AS (
    SELECT
        DENSE_RANK() OVER (ORDER BY condition)::BIGINT AS condition_id,
        condition
    FROM distinct_vals
)
SELECT 0::BIGINT AS condition_id, '(Unknown)' AS condition
UNION ALL
SELECT condition_id, condition FROM ranked
