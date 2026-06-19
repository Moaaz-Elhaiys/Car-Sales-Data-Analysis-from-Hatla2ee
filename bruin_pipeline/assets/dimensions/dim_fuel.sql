/* @bruin

name: marts.dim_fuel
type: pg.sql

description: |
  Fuel dimension. Sentinel row (id=0, fuel='(Unknown)'). The parenthesised
  literal cannot be produced by the INITCAP cleaning in staging.cars, so it
  cannot collide with a real value.

depends:
  - staging.cars

materialization:
  type: table

columns:
  - name: fuel_id
    type: bigint
    checks:
      - name: not_null
      - name: unique
  - name: fuel
    type: text
    checks:
      - name: not_null
      - name: unique

@bruin */

WITH distinct_fuels AS (
    SELECT DISTINCT fuel
    FROM staging.cars
    WHERE fuel IS NOT NULL
      AND fuel <> '(Unknown)'
),
hashed AS (
    -- See dim_brand for the rationale: 60-bit md5 hash gives stable,
    -- deterministic ids that survive `make full-refresh` and never
    -- shift when staging.cars membership changes.
    SELECT
        ('x' || SUBSTR(MD5(fuel), 1, 15))::BIT(60)::BIGINT AS fuel_id,
        fuel
    FROM distinct_fuels
)
SELECT 0::BIGINT AS fuel_id, '(Unknown)' AS fuel
UNION ALL
SELECT fuel_id, fuel FROM hashed
