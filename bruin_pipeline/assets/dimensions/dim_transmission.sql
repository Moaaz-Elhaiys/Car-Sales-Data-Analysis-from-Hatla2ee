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
hashed AS (
    -- See dim_brand for the rationale: 60-bit md5 hash gives stable,
    -- deterministic ids that survive `make full-refresh` and never
    -- shift when staging.cars membership changes.
    SELECT
        ('x' || SUBSTR(MD5(transmission), 1, 15))::BIT(60)::BIGINT AS transmission_id,
        transmission
    FROM distinct_vals
)
SELECT 0::BIGINT AS transmission_id, '(Unknown)' AS transmission
UNION ALL
SELECT transmission_id, transmission FROM hashed
