/* @bruin

name: marts.fact_car_listings
type: pg.sql

description: |
  Central fact table. One row per *observation* of a listing (a snapshot
  at a particular scraped_at), with surrogate-key FKs to every dimension
  and measures (price_egp, km, cc). NULL natural keys in staging.cars
  are mapped to the sentinel id=0 in each dim so the FK columns are
  always populated.

  CC is kept here as an integer measure (rather than a separate dim) --
  raw cc values have high cardinality vs. analytical value and slicing
  by exact engine displacement is uncommon.

  body_style and used_since are *historical-only* attributes carried
  over from a previous pipeline export (see scripts/import_historical_fact.py).
  The current spider does not capture them, so for spider-driven rows
  these columns are always NULL.

  This table is APPEND-ONLY:
    - PK is a synthetic `id` BIGINT generated from a shared sequence
      (marts.fact_car_listings_id_seq, created by sql/init/03_*.sql).
    - There is no `external_id` or `link` column on the fact -- both are
      preserved upstream in raw.cars / staging.cars but the fact is
      anonymous data points keyed only on the surrogate id.
    - Strategy is `append`: each spider transform inserts new rows; an
      existing listing scraped twice produces two fact rows (a snapshot
      time-series). Rows are NEVER updated in place.

  IMPORTANT trade-offs of the append-only design:
    - `make transform` is NOT idempotent within its own window. Running
      it twice in the same window will append the same staging rows
      twice. Run it once per scrape (or use a tight INCREMENTAL_DAYS).
    - `make import-historical` is also NOT idempotent. Re-running it
      duplicates every CSV row. The script prints a warning on every
      run; `TRUNCATE marts.fact_car_listings` first if you intend to
      re-import.
    - `make full-refresh` drops + rebuilds the table from staging
      alone. CSV-loaded historical rows are wiped and must be
      re-imported with `make import-historical`.

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
  strategy: append

columns:
  - name: id
    type: bigint
    description: |
      Surrogate-key primary key. Generated from
      marts.fact_car_listings_id_seq. Has no business meaning -- do not
      expose in dashboards or use as a join key from external systems.
    primary_key: true
    checks:
      - name: not_null
      - name: unique
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
    type: bigint
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
  - name: body_style
    type: text
    description: |
      Body style (Hatchback, Sedan, ...). Historical-only -- carried in
      from import_historical_fact.py. NULL for spider-driven rows.
  - name: used_since
    type: integer
    description: |
      First-use year (e.g. 2014) from the historical export.
      Historical-only; NULL for spider-driven rows.
  - name: scraped_at
    type: timestamptz
    checks:
      - name: not_null
  - name: updated_at
    type: timestamptz
    checks:
      - name: not_null

@bruin */

-- One fact row per staging row in the run window. No dedup on
-- external_id (the fact is append-only and has no natural-key column),
-- so a listing that appears twice in staging.cars under different URL
-- variants becomes two fact rows -- correct behaviour for a
-- snapshot/time-series fact where each observation is distinct.
SELECT
    nextval('marts.fact_car_listings_id_seq')   AS id,
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
    -- body_style / used_since are historical-only; the spider does not
    -- capture them, so we project NULL for spider-driven rows.
    NULL::TEXT    AS body_style,
    NULL::INTEGER AS used_since,
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
WHERE s.updated_at >= '{{ start_timestamp }}'
  AND s.updated_at <  '{{ end_timestamp }}'
