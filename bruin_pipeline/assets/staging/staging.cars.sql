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

-- Cleaned source columns. We compute the title-cased brand/model first so
-- the per-brand model rollup below can match against canonical strings
-- rather than re-running BTRIM/INITCAP a dozen times.
WITH cleaned AS (
    SELECT
        link,
        NULLIF(BTRIM(external_id), '')                                              AS external_id,
        -- price: strip everything that isn't a digit, then cast; NULL if nothing left.
        NULLIF(REGEXP_REPLACE(COALESCE(price, ''), '[^0-9]', '', 'g'), '')::BIGINT  AS price_egp,
        -- km: same idea.
        NULLIF(REGEXP_REPLACE(COALESCE(km, ''), '[^0-9]', '', 'g'), '')::INTEGER    AS km,
        -- cc: same idea.
        NULLIF(REGEXP_REPLACE(COALESCE(cc, ''), '[^0-9]', '', 'g'), '')::INTEGER    AS cc,
        -- model_year: pull the first 4-digit run out of release_year.
        NULLIF(SUBSTRING(COALESCE(release_year, '') FROM '\d{4}'), '')::INTEGER     AS model_year,
        INITCAP(NULLIF(BTRIM(brand), ''))                                           AS brand,
        INITCAP(NULLIF(BTRIM(model), ''))                                           AS model_raw,
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
)
SELECT
    link,
    external_id,
    price_egp,
    km,
    cc,
    model_year,
    brand,
    -- Per-brand model rollup. Most brands keep model_raw as-is. Brands
    -- with high model-variant noise (e.g. Mercedes -- 100+ rows for
    -- ~25 actual model families) get collapsed to family names so
    -- dim_model and downstream charts aren't dominated by trim levels.
    --
    -- ADDING A NEW BRAND ROLLUP:
    --   1. Add a WHEN block below for the brand.
    --   2. Decide overrides (special-case strings) and a fallback rule
    --      (the prefix-before-first-digit-or-space heuristic works for
    --      most letter-and-number naming conventions).
    --
    -- Mercedes rollup: ~106 distinct model strings -> ~25 families.
    -- Pattern: take the leading non-digit, non-space prefix as the
    -- family identifier ("C 200" -> "C", "Cla 45 Amg" -> "Cla", "G63"
    -- -> "G"), then map known prefixes to human-friendly names. Pure
    -- numeric models ("180", "500") -> "Classic". A small override
    -- table handles the strings the heuristic mishandles.
    CASE
        WHEN brand <> 'Mercedes' THEN model_raw

        -- Mercedes overrides (heuristic-doesn't-fit cases)
        WHEN model_raw = 'Sel'                            THEN 'S-Class'
        WHEN model_raw IN ('Amg Gt', 'Gt 43')             THEN 'AMG GT'
        WHEN model_raw IN ('Maybach', 'Maybach Gls')      THEN 'Maybach'
        WHEN model_raw IN ('Viano', 'Vito')               THEN 'V-Class / Vans'
        WHEN model_raw = 'Other'                          THEN 'Other'

        -- Mercedes heuristic: prefix-to-family lookup
        ELSE COALESCE(
            CASE BTRIM(SUBSTRING(model_raw FROM '^[^0-9 ]+'))
                WHEN 'A'   THEN 'A-Class'
                WHEN 'B'   THEN 'B-Class'
                WHEN 'C'   THEN 'C-Class'
                WHEN 'E'   THEN 'E-Class'
                WHEN 'S'   THEN 'S-Class'
                WHEN 'V'   THEN 'V-Class / Vans'
                WHEN 'G'   THEN 'G-Class'
                WHEN 'Gl'  THEN 'GL-Class'
                WHEN 'Gla' THEN 'GLA'
                WHEN 'Glb' THEN 'GLB'
                WHEN 'Glc' THEN 'GLC'
                WHEN 'Gle' THEN 'GLE'
                WHEN 'Glk' THEN 'GLK'
                WHEN 'Gls' THEN 'GLS'
                WHEN 'Cla' THEN 'CLA'
                WHEN 'Cle' THEN 'CLE'
                WHEN 'Cls' THEN 'CLS'
                WHEN 'Sl'  THEN 'SL'
                WHEN 'Slc' THEN 'SLC'
                WHEN 'Slk' THEN 'SLK'
                WHEN 'Eqa' THEN 'EQA'
                WHEN 'Eqb' THEN 'EQB'
                WHEN 'Eqe' THEN 'EQE'
                WHEN 'Eqs' THEN 'EQS'
                WHEN 'Eqv' THEN 'EQV'
                ELSE NULL  -- unmapped prefix; fall through to fallback
            END,
            -- pure-numeric / blank model -> "Classic" (W123/W124-era
            -- names like "180", "200", "500")
            CASE WHEN BTRIM(SUBSTRING(model_raw FROM '^[^0-9 ]+')) IS NULL
                 THEN 'Classic'
            END,
            -- Final fallback: keep the prefix verbatim. Should be rare
            -- in practice; means a Mercedes string we haven't seen
            -- before. Surfacing it here makes it easy to spot in the
            -- dashboard and add to the table above.
            BTRIM(SUBSTRING(model_raw FROM '^[^0-9 ]+'))
        )
    END                                                   AS model,
    condition,
    color,
    fuel,
    transmission,
    location,
    assembly_country,
    scraped_at,
    updated_at
FROM cleaned
