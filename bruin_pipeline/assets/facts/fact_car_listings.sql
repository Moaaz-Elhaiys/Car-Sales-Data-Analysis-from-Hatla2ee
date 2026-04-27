/* @bruin

name: marts.fact_car_listings
type: pg.sql

description: |
  Central fact table. One row per scraped listing, with surrogate-key FKs to
  every dimension and measures (price_egp, km). NULL natural keys in
  staging.cars are mapped to the sentinel id=0 in each dim so the FK columns
  are always populated.

depends:
  - staging.cars
  - marts.dim_make
  - marts.dim_model
  - marts.dim_fuel
  - marts.dim_transmission
  - marts.dim_body_style
  - marts.dim_color
  - marts.dim_city
  - marts.dim_year

materialization:
  type: table

columns:
  - name: link
    type: text
    checks:
      - name: not_null
      - name: unique
  - name: make_id
    type: bigint
    checks:
      - name: not_null
  - name: model_id
    type: bigint
    checks:
      - name: not_null
  - name: fuel_id
    type: bigint
    checks:
      - name: not_null
  - name: transmission_id
    type: bigint
    checks:
      - name: not_null
  - name: body_style_id
    type: bigint
    checks:
      - name: not_null
  - name: color_id
    type: bigint
    checks:
      - name: not_null
  - name: city_id
    type: bigint
    checks:
      - name: not_null
  - name: year_id
    type: bigint
    checks:
      - name: not_null
  - name: price_egp
    type: integer
    checks:
      - name: non_negative
  - name: km
    type: integer
    checks:
      - name: non_negative
  - name: scraped_at
    type: timestamptz
    checks:
      - name: not_null
  - name: updated_at
    type: timestamptz
    checks:
      - name: not_null

@bruin */

SELECT
    s.link,
    COALESCE(dmk.make_id,         0)::BIGINT AS make_id,
    COALESCE(dmd.model_id,        0)::BIGINT AS model_id,
    COALESCE(df.fuel_id,          0)::BIGINT AS fuel_id,
    COALESCE(dt.transmission_id,  0)::BIGINT AS transmission_id,
    COALESCE(dbs.body_style_id,   0)::BIGINT AS body_style_id,
    COALESCE(dc.color_id,         0)::BIGINT AS color_id,
    COALESCE(dci.city_id,         0)::BIGINT AS city_id,
    COALESCE(dy.year_id,          0)::BIGINT AS year_id,
    s.price_egp,
    s.km,
    s.title,
    s.scraped_at,
    s.updated_at
FROM staging.cars s
LEFT JOIN marts.dim_make         dmk ON dmk.make         = s.make
LEFT JOIN marts.dim_model        dmd ON dmd.model        = s.model
                                     AND dmd.make_id     = COALESCE(dmk.make_id, 0)
LEFT JOIN marts.dim_fuel         df  ON df.fuel          = s.fuel
LEFT JOIN marts.dim_transmission dt  ON dt.transmission  = s.transmission
LEFT JOIN marts.dim_body_style   dbs ON dbs.body_style   = s.body_style
LEFT JOIN marts.dim_color        dc  ON dc.color         = s.color
LEFT JOIN marts.dim_city         dci ON dci.city         = s.city
LEFT JOIN marts.dim_year         dy  ON dy.model_year    = s.model_year
