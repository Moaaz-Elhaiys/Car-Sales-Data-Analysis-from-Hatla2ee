/* @bruin

name: marts.dim_brand
type: pg.sql

description: |
  Brand dimension. Includes a sentinel row (id=0, brand='(Unknown)') used
  by the fact table for listings whose source brand was NULL. The
  parenthesised literal can't be produced by the INITCAP cleaning in
  staging.cars, so it cannot collide with a real value.

depends:
  - staging.cars

materialization:
  type: table

columns:
  - name: brand_id
    type: bigint
    checks:
      - name: not_null
      - name: unique
  - name: brand
    type: text
    checks:
      - name: not_null
      - name: unique

@bruin */

WITH distinct_brands AS (
    SELECT DISTINCT brand
    FROM staging.cars
    WHERE brand IS NOT NULL
      AND brand <> '(Unknown)'  -- defensive: never duplicate the sentinel
),
ranked AS (
    SELECT
        DENSE_RANK() OVER (ORDER BY brand)::BIGINT AS brand_id,
        brand
    FROM distinct_brands
)
SELECT 0::BIGINT AS brand_id, '(Unknown)' AS brand
UNION ALL
SELECT brand_id, brand FROM ranked
