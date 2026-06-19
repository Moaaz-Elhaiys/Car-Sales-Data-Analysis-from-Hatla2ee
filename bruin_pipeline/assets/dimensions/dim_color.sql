/* @bruin

name: marts.dim_color
type: pg.sql

description: |
  Color dimension. Sentinel row (id=0, color='(Unknown)'). The parenthesised
  literal cannot be produced by the INITCAP cleaning in staging.cars, so it
  cannot collide with a real value.

depends:
  - staging.cars

materialization:
  type: table

columns:
  - name: color_id
    type: bigint
    checks:
      - name: not_null
      - name: unique
  - name: color
    type: text
    checks:
      - name: not_null
      - name: unique

@bruin */

WITH distinct_vals AS (
    SELECT DISTINCT color
    FROM staging.cars
    WHERE color IS NOT NULL
      AND color <> '(Unknown)'
),
hashed AS (
    -- See dim_brand for the rationale: 60-bit md5 hash gives stable,
    -- deterministic ids that survive `make full-refresh` and never
    -- shift when staging.cars membership changes.
    SELECT
        ('x' || SUBSTR(MD5(color), 1, 15))::BIT(60)::BIGINT AS color_id,
        color
    FROM distinct_vals
)
SELECT 0::BIGINT AS color_id, '(Unknown)' AS color
UNION ALL
SELECT color_id, color FROM hashed
