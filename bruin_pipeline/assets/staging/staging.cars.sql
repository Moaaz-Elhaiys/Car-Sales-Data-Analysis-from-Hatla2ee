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
    -- ~25 actual model families; BMW -- 60+ rows for ~20) get
    -- collapsed to family names so dim_model and downstream charts
    -- aren't dominated by trim levels.
    --
    -- ADDING A NEW BRAND ROLLUP:
    --   1. Add a WHEN block in the outer CASE below for the brand.
    --   2. Decide overrides (special-case strings) and a fallback
    --      rule. Prefix-before-first-digit-or-space works for
    --      letter-and-number naming (Mercedes); first-digit-of-the-
    --      number for series-numbered brands (BMW); prefix-LIKE for
    --      brands with a few noisy variants (Hyundai, Volkswagen).
    CASE
        --
        -- Mercedes rollup: ~106 distinct model strings -> ~25 families.
        -- Pattern: take the leading non-digit, non-space prefix as the
        -- family identifier ("C 200" -> "C", "Cla 45 Amg" -> "Cla",
        -- "G63" -> "G"), then map known prefixes to human-friendly
        -- names. Pure numeric models ("180", "500") -> "Classic". A
        -- small override table handles the strings the heuristic
        -- mishandles.
        --
        WHEN brand = 'Mercedes' THEN
            CASE
                -- Mercedes overrides (heuristic-doesn't-fit cases)
                WHEN model_raw = 'Sel'                       THEN 'S-Class'
                WHEN model_raw IN ('Amg Gt', 'Gt 43')        THEN 'AMG GT'
                WHEN model_raw IN ('Maybach', 'Maybach Gls') THEN 'Maybach'
                WHEN model_raw IN ('Viano', 'Vito')          THEN 'V-Class / Vans'
                WHEN model_raw = 'Other'                     THEN 'Other'
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
            END

        --
        -- BMW rollup: ~61 distinct model strings -> ~20 families.
        -- Pattern: BMW's numbered series share their hundreds digit
        -- (320/330/340 are all 3-Series; 530/535 are 5-Series). The
        -- rollup recognizes this plus the M / X / i / iX / Z
        -- sub-brands.
        --
        WHEN brand = 'Bmw' THEN
            CASE
                -- BMW overrides
                WHEN model_raw = 'Other'                                       THEN 'Other'
                WHEN model_raw = 'Gran Coupe'                                  THEN 'Gran Coupe'
                -- "1 Series" / "3 Series" / etc. already named -> keep as-is
                WHEN model_raw ~ '^[1-8] Series$'                              THEN model_raw
                -- M Series (M3, M4, M5, M235i, M850): performance sub-brand
                WHEN model_raw ~ '^M[0-9]'                                     THEN 'M Series'
                -- X SUVs (X1..X7, including M variants like X3 M / X4m / X5 M)
                WHEN model_raw ~ '^X[1-7]'                                     THEN 'X' || SUBSTRING(model_raw FROM 2 FOR 1)
                -- i electric (I3, I4, I5, I7): roll into one "i Series" family
                WHEN model_raw ~ '^I[0-9]+$'                                   THEN 'i Series'
                -- iX electric SUV (Ix, Ix1, Ix3): roll into one "iX" family
                WHEN model_raw ~ '^Ix'                                         THEN 'iX'
                -- Z roadsters (Z4, Z4 M40)
                WHEN model_raw ~ '^Z[0-9]'                                     THEN 'Z' || SUBSTRING(model_raw FROM 2 FOR 1)
                -- Numbered model: hundreds digit = series number (116/118
                -- -> 1 Series; 320/330/340 -> 3 Series; 530 E / 760i -> 5/7)
                WHEN model_raw ~ '^[1-8][0-9][0-9]'                            THEN SUBSTRING(model_raw FROM 1 FOR 1) || ' Series'
                -- Fallback: pass through unrecognized strings
                ELSE model_raw
            END

        --
        -- Hyundai rollup: ~45 -> ~37. Conservative; only collapsing
        -- the obvious noisy variant explosions (Accent / Elantra /
        -- Tucson / H Series). Avante stays separate from Elantra (it's
        -- the same car under a different market badge but the listings
        -- use different names; treating them as one would lose the
        -- search distinction for buyers).
        --
        WHEN brand = 'Hyundai' THEN
            CASE
                WHEN model_raw LIKE 'Accent%'    THEN 'Accent'
                WHEN model_raw LIKE 'Elantra%'   THEN 'Elantra'
                WHEN model_raw LIKE 'Tucson%'    THEN 'Tucson'
                WHEN model_raw IN ('H1', 'H100') THEN 'H Series'
                ELSE model_raw
            END

        --
        -- Volkswagen rollup: ~38 -> ~26. Golf has 9 generations as
        -- distinct rows (Golf, Golf 2..8, Golf R) and ID has 5
        -- variants (Id 4 / Id 6 / Id Unyx / Id3 / Id7).
        --
        WHEN brand = 'Volkswagen' THEN
            CASE
                WHEN model_raw LIKE 'Golf%' THEN 'Golf'
                WHEN model_raw LIKE 'Id%'   THEN 'ID Series'
                ELSE model_raw
            END

        ELSE model_raw
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
