/* @bruin

name: marts.dim_year
type: pg.sql

description: |
  Year dimension built from staging.cars.model_year. Includes a sentinel
  row (id=0, model_year=NULL, decade=NULL) for listings with an unparseable
  used_since value.

depends:
  - staging.cars

materialization:
  type: table

columns:
  - name: year_id
    type: bigint
    checks:
      - name: not_null
      - name: unique
  - name: model_year
    type: integer
  - name: decade
    type: integer

@bruin */

WITH distinct_years AS (
    SELECT DISTINCT model_year
    FROM staging.cars
    WHERE model_year IS NOT NULL
),
hashed AS (
    -- See dim_brand for the rationale: 60-bit md5 hash gives stable,
    -- deterministic ids that survive `make full-refresh` and never
    -- shift when staging.cars membership changes.
    SELECT
        ('x' || SUBSTR(MD5(model_year::TEXT), 1, 15))::BIT(60)::BIGINT AS year_id,
        model_year,
        (model_year / 10) * 10 AS decade
    FROM distinct_years
)
SELECT 0::BIGINT AS year_id, NULL::INTEGER AS model_year, NULL::INTEGER AS decade
UNION ALL
SELECT year_id, model_year, decade FROM hashed
