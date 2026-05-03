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

  body_style and used_since are *historical-only* attributes carried over
  from a previous pipeline export (see scripts/import_historical_fact.py).
  The current spider does not capture them, so for spider-driven rows
  these columns are always NULL. They have no `update_on_merge` flag, so
  the merge UPDATE never overwrites a CSV-loaded value with a NULL when
  the spider re-scrapes the same external_id.

  Loaded incrementally with the `merge` strategy on `external_id` (cast
  to BIGINT, the numeric tail of every hatla2ee listing URL and the
  natural identity of a listing on their side). `link` is intentionally
  *not* a column on this fact table -- URLs can change shape (paths,
  query strings, fragments) while the numeric listing id is stable, so
  external_id is the more reliable join key for downstream Power BI
  models.

  The source query filters staging.cars by updated_at against the run
  window, so scheduled re-runs only touch rows the spider modified since
  the last run. CSV-loaded historical rows have no matching staging.cars
  row, so the merge never touches them -- they live in the table as long
  as the table itself does.

  WARNING: `make full-refresh` drops and rebuilds the table from staging
  alone. Any rows previously inserted by import_historical_fact.py are
  wiped and must be re-imported. The import script is idempotent
  (`WHERE NOT EXISTS` on external_id), so re-running it is safe.

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
  strategy: merge

columns:
  - name: external_id
    type: bigint
    description: |
      Numeric listing id from hatla2ee, parsed from the tail of the
      listing URL. This is the fact-table primary key and the merge
      key for both spider-driven incremental loads and the historical
      CSV importer.
    primary_key: true
    checks:
      - name: not_null
      - name: unique
  - name: brand_id
    type: bigint
    update_on_merge: true
    checks:
      - name: not_null
  - name: model_id
    type: bigint
    update_on_merge: true
    checks:
      - name: not_null
  - name: condition_id
    type: bigint
    update_on_merge: true
    checks:
      - name: not_null
  - name: color_id
    type: bigint
    update_on_merge: true
    checks:
      - name: not_null
  - name: fuel_id
    type: bigint
    update_on_merge: true
    checks:
      - name: not_null
  - name: transmission_id
    type: bigint
    update_on_merge: true
    checks:
      - name: not_null
  - name: location_id
    type: bigint
    update_on_merge: true
    checks:
      - name: not_null
  - name: assembly_country_id
    type: bigint
    update_on_merge: true
    checks:
      - name: not_null
  - name: year_id
    type: bigint
    update_on_merge: true
    checks:
      - name: not_null
  - name: price_egp
    type: bigint
    update_on_merge: true
    checks:
      - name: non_negative
  - name: km
    type: integer
    update_on_merge: true
    checks:
      - name: non_negative
  - name: cc
    type: integer
    description: Engine displacement in cubic centimetres. Measure (no FK).
    update_on_merge: true
    checks:
      - name: non_negative
  - name: body_style
    type: text
    description: |
      Body style (Hatchback, Sedan, ...). Historical-only -- carried in
      from import_historical_fact.py. NULL for spider-driven rows. Not
      flagged update_on_merge so a spider re-scrape of the same
      external_id doesn't overwrite it with NULL.
  - name: used_since
    type: integer
    description: |
      First-use year (e.g. 2014) from the historical export. Historical-
      only; NULL for spider-driven rows. Not flagged update_on_merge.
  - name: scraped_at
    type: timestamptz
    update_on_merge: true
    checks:
      - name: not_null
  - name: updated_at
    type: timestamptz
    update_on_merge: true
    checks:
      - name: not_null

@bruin */

-- staging.cars is keyed on link (its merge primary_key), so the same
-- listing can appear under multiple URL variants (trailing slash, query
-- string, ...). external_id is the fact-table PK -- collapse any
-- in-window duplicates here, keeping the freshest row per id (latest
-- updated_at, then scraped_at, then link as a deterministic
-- tiebreaker). The updated_at window filter MUST live inside the CTE:
-- if it lived in the outer WHERE, a backfill of an old window could
-- pick an out-of-window newer row that the outer filter then drops,
-- silently losing the listing from the rebuild.
WITH staging_dedup AS (
    SELECT DISTINCT ON (s.external_id) s.*
    FROM staging.cars s
    WHERE s.external_id IS NOT NULL
      AND s.external_id ~ '^\d+$'
      AND s.updated_at >= '{{ start_timestamp }}'
      AND s.updated_at <  '{{ end_timestamp }}'
    ORDER BY s.external_id, s.updated_at DESC, s.scraped_at DESC, s.link
)
SELECT
    s.external_id::BIGINT                       AS external_id,
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
    -- capture them. We project NULL so the SELECT shape matches the
    -- declared columns; without `update_on_merge` on those columns the
    -- merge UPDATE never overwrites a CSV-loaded value with this NULL.
    NULL::TEXT    AS body_style,
    NULL::INTEGER AS used_since,
    s.scraped_at,
    s.updated_at
FROM staging_dedup s
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
