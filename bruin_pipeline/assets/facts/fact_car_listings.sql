/* @bruin

name: marts.fact_car_listings
type: pg.sql

description: |
  Central fact table. One row per scraped listing, with surrogate-key FKs
  to every dimension and measures (price_egp, km, cc). NULL natural keys
  in staging.cars are mapped to the sentinel id=0 in each dim so the FK
  columns are always populated.

  CC is kept here as an integer measure (rather than a separate dim) --
  raw cc values have high cardinality vs. analytical value and slicing by
  exact engine displacement is uncommon.

depends:
  - staging.cars
  - marts.dim_brand
  - marts.dim_model
  - marts.dim_condition
  - marts.dim_color
  - marts.dim_fuel
  - marts.dim_transmission
  - marts.dim_location
  - marts.dim_assembly_country
  - marts.dim_year

materialization:
  type: table

columns:
  - name: link
    type: text
    checks:
      - name: not_null
      - name: unique
  - name: external_id
    type: text
    description: Numeric id parsed from the tail of the listing URL.
  - name: brand_id
    type: bigint
    checks:
      - name: not_null
  - name: model_id
    type: bigint
    checks:
      - name: not_null
  - name: condition_id
    type: bigint
    checks:
      - name: not_null
  - name: color_id
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
  - name: location_id
    type: bigint
    checks:
      - name: not_null
  - name: assembly_country_id
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
  - name: cc
    type: integer
    description: Engine displacement in cubic centimetres. Measure (no FK).
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
    s.external_id,
    COALESCE(db.brand_id,            0)::BIGINT AS brand_id,
    COALESCE(dmd.model_id,           0)::BIGINT AS model_id,
    COALESCE(dcond.condition_id,     0)::BIGINT AS condition_id,
    COALESCE(dcol.color_id,          0)::BIGINT AS color_id,
    COALESCE(df.fuel_id,             0)::BIGINT AS fuel_id,
    COALESCE(dt.transmission_id,     0)::BIGINT AS transmission_id,
    COALESCE(dloc.location_id,       0)::BIGINT AS location_id,
    COALESCE(dac.assembly_country_id,0)::BIGINT AS assembly_country_id,
    COALESCE(dy.year_id,             0)::BIGINT AS year_id,
    s.price_egp,
    s.km,
    s.cc,
    s.scraped_at,
    s.updated_at
FROM staging.cars s
LEFT JOIN marts.dim_brand            db    ON db.brand              = s.brand
LEFT JOIN marts.dim_model            dmd   ON dmd.model             = s.model
                                          AND dmd.brand_id          = COALESCE(db.brand_id, 0)
LEFT JOIN marts.dim_condition        dcond ON dcond.condition       = s.condition
LEFT JOIN marts.dim_color            dcol  ON dcol.color            = s.color
LEFT JOIN marts.dim_fuel             df    ON df.fuel               = s.fuel
LEFT JOIN marts.dim_transmission     dt    ON dt.transmission       = s.transmission
LEFT JOIN marts.dim_location         dloc  ON dloc.location         = s.location
LEFT JOIN marts.dim_assembly_country dac   ON dac.assembly_country  = s.assembly_country
LEFT JOIN marts.dim_year             dy    ON dy.model_year         = s.model_year
