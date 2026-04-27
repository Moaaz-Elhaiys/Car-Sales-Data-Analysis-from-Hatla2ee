/* @bruin

name: marts.dim_color
type: pg.sql

description: Color dimension. Sentinel row (id=0, color='Unknown').

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

@bruin */

WITH distinct_vals AS (
    SELECT DISTINCT color
    FROM staging.cars
    WHERE color IS NOT NULL
),
ranked AS (
    SELECT
        DENSE_RANK() OVER (ORDER BY color)::BIGINT AS color_id,
        color
    FROM distinct_vals
)
SELECT 0::BIGINT AS color_id, 'Unknown' AS color
UNION ALL
SELECT color_id, color FROM ranked
