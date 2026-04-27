/* @bruin

name: marts.dim_make
type: pg.sql

description: |
  Make dimension. Includes a sentinel row (id=0, make='(Unknown)') used by
  the fact table for listings whose source make was NULL. The parenthesised
  literal can't be produced by the INITCAP cleaning in staging.cars, so it
  cannot collide with a real value.

depends:
  - staging.cars

materialization:
  type: table

columns:
  - name: make_id
    type: bigint
    checks:
      - name: not_null
      - name: unique
  - name: make
    type: text
    checks:
      - name: not_null
      - name: unique

@bruin */

WITH distinct_makes AS (
    SELECT DISTINCT make
    FROM staging.cars
    WHERE make IS NOT NULL
      AND make <> '(Unknown)'  -- defensive: never duplicate the sentinel
),
ranked AS (
    SELECT
        DENSE_RANK() OVER (ORDER BY make)::BIGINT AS make_id,
        make
    FROM distinct_makes
)
SELECT 0::BIGINT AS make_id, '(Unknown)' AS make
UNION ALL
SELECT make_id, make FROM ranked
