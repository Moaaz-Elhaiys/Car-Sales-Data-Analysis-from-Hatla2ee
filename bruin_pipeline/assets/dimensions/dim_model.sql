/* @bruin

name: marts.dim_model
type: pg.sql

description: |
  Model dimension. Carries brand_id so the fact table only needs model_id.
  Rows with a model but no brand are linked to the '(Unknown)' brand
  sentinel. The parenthesised sentinel literal cannot be produced by
  INITCAP, so it cannot collide with real input. Note: model alone is
  *not* unique (the same model name can appear under different brands),
  so the unique check is on `model_id` only — a `(model, brand_id)`
  natural key is implicitly unique by construction (DISTINCT in the CTE).

depends:
  - staging.cars
  - marts.dim_brand

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
  - name: brand_id
    type: bigint
    checks:
      - name: not_null

@bruin */

WITH distinct_models AS (
    SELECT DISTINCT
        s.model,
        COALESCE(b.brand_id, 0) AS brand_id
    FROM staging.cars s
    LEFT JOIN marts.dim_brand b ON b.brand = s.brand
    WHERE s.model IS NOT NULL
      AND s.model <> '(Unknown)'  -- defensive: never duplicate the sentinel
),
ranked AS (
    SELECT
        DENSE_RANK() OVER (ORDER BY model, brand_id)::BIGINT AS model_id,
        model,
        brand_id
    FROM distinct_models
)
SELECT 0::BIGINT AS model_id, '(Unknown)' AS model, 0::BIGINT AS brand_id
UNION ALL
SELECT model_id, model, brand_id FROM ranked
