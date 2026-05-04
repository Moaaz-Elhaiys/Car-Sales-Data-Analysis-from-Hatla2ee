/* @bruin

name: marts.dim_location
type: pg.sql

description: |
  Location dimension (city / governorate from the listing). Sentinel row
  (id=0, location='(Unknown)'). The parenthesised literal cannot be
  produced by the INITCAP cleaning in staging.cars, so it cannot collide
  with a real value.

depends:
  - staging.cars

materialization:
  type: table

columns:
  - name: location_id
    type: bigint
    checks:
      - name: not_null
      - name: unique
  - name: location
    type: text
    checks:
      - name: not_null
      - name: unique

@bruin */

WITH distinct_vals AS (
    SELECT DISTINCT location
    FROM staging.cars
    WHERE location IS NOT NULL
      AND location <> '(Unknown)'
),
hashed AS (
    -- See dim_brand for the rationale: 60-bit md5 hash gives stable,
    -- deterministic ids that survive `make full-refresh` and never
    -- shift when staging.cars membership changes.
    SELECT
        ('x' || SUBSTR(MD5(location), 1, 15))::BIT(60)::BIGINT AS location_id,
        location
    FROM distinct_vals
)
SELECT 0::BIGINT AS location_id, '(Unknown)' AS location
UNION ALL
SELECT location_id, location FROM hashed
