/* @bruin

name: marts.dim_body_style
type: pg.sql

description: |
  Body-style dimension. Sentinel row (id=0, body_style='(Unknown)'). The
  parenthesised literal cannot be produced by the INITCAP cleaning in
  staging.cars, so it cannot collide with a real value.

depends:
  - staging.cars

materialization:
  type: table

columns:
  - name: body_style_id
    type: bigint
    checks:
      - name: not_null
      - name: unique
  - name: body_style
    type: text
    checks:
      - name: not_null
      - name: unique

@bruin */

WITH distinct_vals AS (
    SELECT DISTINCT body_style
    FROM staging.cars
    WHERE body_style IS NOT NULL
      AND body_style <> '(Unknown)'
),
ranked AS (
    SELECT
        DENSE_RANK() OVER (ORDER BY body_style)::BIGINT AS body_style_id,
        body_style
    FROM distinct_vals
)
SELECT 0::BIGINT AS body_style_id, '(Unknown)' AS body_style
UNION ALL
SELECT body_style_id, body_style FROM ranked
