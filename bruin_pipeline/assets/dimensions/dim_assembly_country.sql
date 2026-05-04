/* @bruin

name: marts.dim_assembly_country
type: pg.sql

description: |
  Assembly-country dimension (where the unit was assembled). Often sparse
  on used-car listings -- those rows route to the sentinel id=0. The
  parenthesised '(Unknown)' literal cannot be produced by the INITCAP
  cleaning in staging.cars, so it cannot collide with a real value.

depends:
  - staging.cars

materialization:
  type: table

columns:
  - name: assembly_country_id
    type: bigint
    checks:
      - name: not_null
      - name: unique
  - name: assembly_country
    type: text
    checks:
      - name: not_null
      - name: unique

@bruin */

WITH distinct_vals AS (
    SELECT DISTINCT assembly_country
    FROM staging.cars
    WHERE assembly_country IS NOT NULL
      AND assembly_country <> '(Unknown)'
),
hashed AS (
    -- See dim_brand for the rationale: 60-bit md5 hash gives stable,
    -- deterministic ids that survive `make full-refresh` and never
    -- shift when staging.cars membership changes.
    SELECT
        ('x' || SUBSTR(MD5(assembly_country), 1, 15))::BIT(60)::BIGINT AS assembly_country_id,
        assembly_country
    FROM distinct_vals
)
SELECT 0::BIGINT AS assembly_country_id, '(Unknown)' AS assembly_country
UNION ALL
SELECT assembly_country_id, assembly_country FROM hashed
