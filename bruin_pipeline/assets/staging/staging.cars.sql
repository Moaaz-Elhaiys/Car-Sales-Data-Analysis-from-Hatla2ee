/* @bruin

name: staging.cars
type: pg.sql

description: |
  Cleaned + typed view of raw.cars. Strings are trimmed and title-cased,
  numeric fields are cast (NULL on non-numeric), and a 4-digit model_year
  is parsed out of the free-text used_since column.

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
  - name: title
    type: text
    update_on_merge: true
  - name: price_egp
    type: integer
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
  - name: model_year
    type: integer
    description: 4-digit year parsed from used_since. NULL if no year present.
    update_on_merge: true
  - name: make
    type: text
    update_on_merge: true
  - name: model
    type: text
    update_on_merge: true
  - name: fuel
    type: text
    update_on_merge: true
  - name: transmission
    type: text
    update_on_merge: true
  - name: color
    type: text
    update_on_merge: true
  - name: class
    type: text
    update_on_merge: true
  - name: body_style
    type: text
    update_on_merge: true
  - name: city
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
    NULLIF(BTRIM(title), '')                                          AS title,
    -- price: strip everything that isn't a digit, then cast; NULL if nothing left.
    NULLIF(REGEXP_REPLACE(COALESCE(price, ''), '[^0-9]', '', 'g'), '')::INTEGER AS price_egp,
    -- km: same idea.
    NULLIF(REGEXP_REPLACE(COALESCE(km, ''), '[^0-9]', '', 'g'), '')::INTEGER    AS km,
    -- model_year: pull the first 4-digit run out of used_since.
    NULLIF(SUBSTRING(COALESCE(used_since, '') FROM '\d{4}'), '')::INTEGER       AS model_year,
    INITCAP(NULLIF(BTRIM(make), ''))                                  AS make,
    INITCAP(NULLIF(BTRIM(model), ''))                                 AS model,
    INITCAP(NULLIF(BTRIM(fuel), ''))                                  AS fuel,
    INITCAP(NULLIF(BTRIM(transmission), ''))                          AS transmission,
    INITCAP(NULLIF(BTRIM(color), ''))                                 AS color,
    INITCAP(NULLIF(BTRIM(class), ''))                                 AS class,
    INITCAP(NULLIF(BTRIM(body_style), ''))                            AS body_style,
    INITCAP(NULLIF(BTRIM(city), ''))                                  AS city,
    scraped_at,
    updated_at
FROM raw.cars
WHERE updated_at >= '{{ start_timestamp }}'
  AND updated_at <  '{{ end_timestamp }}'
