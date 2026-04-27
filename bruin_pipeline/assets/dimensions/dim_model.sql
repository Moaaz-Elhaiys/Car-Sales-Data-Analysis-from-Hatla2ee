/* @bruin

name: marts.dim_model
type: pg.sql

description: |
  Model dimension. Carries make_id so the fact table only needs model_id.
  Rows with a model but no make are linked to the 'Unknown' make sentinel.

depends:
  - staging.cars
  - marts.dim_make

materialization:
  type: table

columns:
  - name: model_id
    type: bigint
    checks:
      - name: not_null
      - name: unique
  - name: model
    type: text
    checks:
      - name: not_null
  - name: make_id
    type: bigint
    checks:
      - name: not_null

@bruin */

WITH distinct_models AS (
    SELECT DISTINCT
        s.model,
        COALESCE(m.make_id, 0) AS make_id
    FROM staging.cars s
    LEFT JOIN marts.dim_make m ON m.make = s.make
    WHERE s.model IS NOT NULL
),
ranked AS (
    SELECT
        DENSE_RANK() OVER (ORDER BY model, make_id)::BIGINT AS model_id,
        model,
        make_id
    FROM distinct_models
)
SELECT 0::BIGINT AS model_id, 'Unknown' AS model, 0::BIGINT AS make_id
UNION ALL
SELECT model_id, model, make_id FROM ranked
