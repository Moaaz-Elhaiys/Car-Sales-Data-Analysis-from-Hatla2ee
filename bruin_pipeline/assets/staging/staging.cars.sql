/* @bruin

name: staging.cars
type: pg.sql

description: |
  Cleaned + typed view of raw.cars. Strings are trimmed and title-cased,
  numeric fields are cast (NULL on non-numeric), and a 4-digit model_year
  is parsed out of the free-text used_since column.

materialization:
  type: table

columns:
  - name: link
    type: text
    description: Source URL for the listing. Natural key.
    checks:
      - name: not_null
      - name: unique
  - name: price_egp
    type: integer
    description: Listing price in EGP. NULL when raw price is empty/garbage.
    checks:
      - name: non_negative
  - name: km
    type: integer
    description: Odometer reading in kilometres. NULL when raw km is garbage.
    checks:
      - name: non_negative
  - name: model_year
    type: integer
    description: 4-digit year parsed from used_since. NULL if no year present.
  - name: make
    type: text
  - name: model
    type: text
  - name: fuel
    type: text
  - name: transmission
    type: text
  - name: color
    type: text
  - name: class
    type: text
  - name: body_style
    type: text
  - name: city
    type: text
  - name: title
    type: text
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
