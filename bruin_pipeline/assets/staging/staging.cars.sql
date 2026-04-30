/* @bruin

name: staging.cars
type: pg.sql

description: |
  Cleaned + typed view of raw.cars. Strings are trimmed and title-cased,
  numeric fields are cast (NULL on non-numeric), and a 4-digit model_year
  is parsed out of release_year.

  Loaded incrementally with the `merge` strategy on `link` (the natural
  key). The source query filters raw.cars by `updated_at` against the run
  window (Bruin injects {{ start_timestamp }} / {{ end_timestamp }}), so
  scheduled re-runs only touch rows the spider modified since the last
  run. New rows are inserted; existing rows whose source data changed
  (e.g. price drop) are updated in place.

  Time zone: raw.cars.updated_at is `timestamptz` and is set by the
  Postgres trigger in sql/init/02_raw_cars.sql via NOW(), which Postgres
  stores as UTC. The Makefile derives the window boundaries with
  `date -u`, so both sides of the comparison live in UTC and there's no
  off-by-one-day risk around DST or local-time shifts.

  For a clean rebuild, run `make full-refresh` (which expands the window
  to cover all of raw.cars).

materialization:
  type: table
  strategy: merge

columns:
  - name: link
    type: text
    description: Source URL for the listing. Natural key.
    primary_key: true
    checks:
      - name: not_null
      - name: unique
  - name: external_id
    type: text
    description: Numeric id parsed from the tail of the listing URL.
    update_on_merge: true
  - name: price_egp
    type: bigint
    description: Listing price in EGP. NULL when raw price is empty/garbage.
    update_on_merge: true
    checks:
      - name: non_negative
  - name: km
    type: integer
    description: Odometer reading in kilometres. NULL when raw km is garbage.
    update_on_merge: true
    checks:
      - name: non_negative
  - name: cc
    type: integer
    description: Engine displacement in cubic centimetres. NULL when raw cc is garbage.
    update_on_merge: true
    checks:
      - name: non_negative
  - name: model_year
    type: integer
    description: 4-digit year parsed from release_year. NULL if no year present.
    update_on_merge: true
  - name: brand
    type: text
    update_on_merge: true
  - name: model
    type: text
    update_on_merge: true
  - name: condition
    type: text
    update_on_merge: true
  - name: color
    type: text
    update_on_merge: true
  - name: fuel
    type: text
    update_on_merge: true
  - name: transmission
    type: text
    update_on_merge: true
  - name: location
    type: text
    update_on_merge: true
  - name: assembly_country
    type: text
    update_on_merge: true
  - name: scraped_at
    type: timestamptz
    update_on_merge: true
    checks:
      - name: not_null
  - name: updated_at
    type: timestamptz
    description: Source mutation timestamp. Drives the incremental window.
    update_on_merge: true
    checks:
      - name: not_null

@bruin */

SELECT
    link,
    NULLIF(BTRIM(external_id), '')                                              AS external_id,
    -- price: strip everything that isn't a digit, then cast; NULL if nothing left.
    NULLIF(REGEXP_REPLACE(COALESCE(price, ''), '[^0-9]', '', 'g'), '')::BIGINT AS price_egp,
    -- km: same idea.
    NULLIF(REGEXP_REPLACE(COALESCE(km, ''), '[^0-9]', '', 'g'), '')::INTEGER    AS km,
    -- cc: same idea.
    NULLIF(REGEXP_REPLACE(COALESCE(cc, ''), '[^0-9]', '', 'g'), '')::INTEGER    AS cc,
    -- model_year: pull the first 4-digit run out of release_year.
    NULLIF(SUBSTRING(COALESCE(release_year, '') FROM '\d{4}'), '')::INTEGER     AS model_year,
    INITCAP(NULLIF(BTRIM(brand), ''))                                           AS brand,
    INITCAP(NULLIF(BTRIM(model), ''))                                           AS model,
    INITCAP(NULLIF(BTRIM(condition), ''))                                       AS condition,
    INITCAP(NULLIF(BTRIM(color), ''))                                           AS color,
    INITCAP(NULLIF(BTRIM(fuel), ''))                                            AS fuel,
    INITCAP(NULLIF(BTRIM(transmission), ''))                                    AS transmission,
    INITCAP(NULLIF(BTRIM(location), ''))                                        AS location,
    -- origin_country is intentionally NOT projected here: hatla2ee used-car
    -- listings don't carry it. We derive origin from brand in marts.dim_brand
    -- via a hardcoded mapping instead.
    INITCAP(NULLIF(BTRIM(assembly_country), ''))                                AS assembly_country,
    scraped_at,
    updated_at
FROM raw.cars
WHERE updated_at >= '{{ start_timestamp }}'
  AND updated_at <  '{{ end_timestamp }}'
