/* @bruin

name: marts.dim_brand
type: pg.sql

description: |
  Brand dimension. Includes a sentinel row (id=0, brand='(Unknown)') used
  by the fact table for listings whose source brand was NULL. The
  parenthesised literal can't be produced by the INITCAP cleaning in
  staging.cars, so it cannot collide with a real value.

  origin_country is hard-coded here via a CASE expression keyed off the
  cleaned brand. hatla2ee detail pages for used cars don't carry an
  origin-country field, so deriving it from the well-known brand → HQ
  mapping is the only way to make this attribute analytically useful.
  Brands we couldn't confidently map (Kyc, Rox, Sandstorm, "Other")
  fall through to '(Unknown)'. Edge calls (per user decision):
    - Mg       -> China  (current owner SAIC, not UK heritage)
    - Speranza -> South Korea (Daewoo-licensed assembly in Egypt)
    - Mini / Lotus / Volvo -> kept on their heritage country, since
      ownership changes are not a strong signal of origin in this
      context.

depends:
  - staging.cars

materialization:
  type: table

columns:
  - name: brand_id
    type: bigint
    checks:
      - name: not_null
      - name: unique
  - name: brand
    type: text
    checks:
      - name: not_null
      - name: unique
  - name: origin_country
    type: text
    description: HQ / heritage country derived from the brand via a hardcoded mapping.
    checks:
      - name: not_null

@bruin */

WITH distinct_brands AS (
    SELECT DISTINCT brand
    FROM staging.cars
    WHERE brand IS NOT NULL
      AND brand <> '(Unknown)'  -- defensive: never duplicate the sentinel
),
hashed AS (
    -- 60-bit md5 hash of the brand name. Deterministic: same brand text
    -- always produces the same brand_id, independent of other rows or
    -- ordering. Stable across `make full-refresh`, prevents FK rot in
    -- downstream fact rows when staging.cars membership changes. The
    -- 60-bit cast keeps the value in the non-negative bigint range
    -- (0, 2^60) -- ~1.15e18 unique values, far more than the brand space.
    SELECT
        ('x' || SUBSTR(MD5(brand), 1, 15))::BIT(60)::BIGINT AS brand_id,
        brand
    FROM distinct_brands
),
all_rows AS (
    SELECT 0::BIGINT AS brand_id, '(Unknown)'::TEXT AS brand
    UNION ALL
    SELECT brand_id, brand FROM hashed
)
SELECT
    brand_id,
    brand,
    CASE brand
        -- Italy
        WHEN 'Abarth'        THEN 'Italy'
        WHEN 'Alfa Romeo'    THEN 'Italy'
        WHEN 'Fiat'          THEN 'Italy'
        WHEN 'Lamborghini'   THEN 'Italy'
        WHEN 'Lancia'        THEN 'Italy'
        WHEN 'Maserati'      THEN 'Italy'
        WHEN 'Wingamm'       THEN 'Italy'
        -- Japan
        WHEN 'Acura'         THEN 'Japan'
        WHEN 'Daihatsu'      THEN 'Japan'
        WHEN 'Honda'         THEN 'Japan'
        WHEN 'Infiniti'      THEN 'Japan'
        WHEN 'Isuzu'         THEN 'Japan'
        WHEN 'Lexus'         THEN 'Japan'
        WHEN 'Mazda'         THEN 'Japan'
        WHEN 'Mitsubishi'    THEN 'Japan'
        WHEN 'Nissan'        THEN 'Japan'
        WHEN 'Subaru'        THEN 'Japan'
        WHEN 'Suzuki'        THEN 'Japan'
        WHEN 'Toyota'        THEN 'Japan'
        -- China
        WHEN 'Aito'          THEN 'China'
        WHEN 'Arcfox'        THEN 'China'
        WHEN 'Avatr'         THEN 'China'
        WHEN 'Baic'          THEN 'China'
        WHEN 'Bestune'       THEN 'China'
        WHEN 'Brilliance'    THEN 'China'
        WHEN 'Byd'           THEN 'China'
        WHEN 'Canghe'        THEN 'China'
        WHEN 'Chana'         THEN 'China'
        WHEN 'Changan'       THEN 'China'
        WHEN 'Chery'         THEN 'China'
        WHEN 'Deepal'        THEN 'China'
        WHEN 'Dfsk'          THEN 'China'
        WHEN 'Dongfeng'      THEN 'China'
        WHEN 'Emgrand'       THEN 'China'
        WHEN 'Exeed'         THEN 'China'
        WHEN 'Faw'           THEN 'China'
        WHEN 'Forthing'      THEN 'China'
        WHEN 'Foton'         THEN 'China'
        WHEN 'Gac'           THEN 'China'
        WHEN 'Geely'         THEN 'China'
        WHEN 'Great Wall'    THEN 'China'
        WHEN 'Haima'         THEN 'China'
        WHEN 'Haval'         THEN 'China'
        WHEN 'Hongqi'        THEN 'China'
        WHEN 'Jac'           THEN 'China'
        WHEN 'Jetour'        THEN 'China'
        WHEN 'Jmc'           THEN 'China'
        WHEN 'Kaiyi'         THEN 'China'
        WHEN 'Karry'         THEN 'China'
        WHEN 'Keyton'        THEN 'China'
        WHEN 'King Long'     THEN 'China'
        WHEN 'Lifan'         THEN 'China'
        WHEN 'Lynkco'        THEN 'China'
        WHEN 'Mg'            THEN 'China'   -- per user: current SAIC owner, not UK heritage
        WHEN 'Senova'        THEN 'China'
        WHEN 'Shineray'      THEN 'China'
        WHEN 'Sokon'         THEN 'China'
        WHEN 'Soueast'       THEN 'China'
        WHEN 'Voyah'         THEN 'China'
        WHEN 'Xiaomi'        THEN 'China'
        WHEN 'Xpeng'         THEN 'China'
        WHEN 'Zeekr'         THEN 'China'
        WHEN 'Zna'           THEN 'China'
        WHEN 'Zotye'         THEN 'China'
        -- USA
        WHEN 'Cadillac'      THEN 'USA'
        WHEN 'Chevrolet'     THEN 'USA'
        WHEN 'Chrysler'      THEN 'USA'
        WHEN 'Dodge'         THEN 'USA'
        WHEN 'Ford'          THEN 'USA'
        WHEN 'Gmc'           THEN 'USA'
        WHEN 'Hummer'        THEN 'USA'
        WHEN 'Jeep'          THEN 'USA'
        WHEN 'Lincoln'       THEN 'USA'
        WHEN 'Tesla'         THEN 'USA'
        -- Germany
        WHEN 'Audi'          THEN 'Germany'
        WHEN 'Bmw'           THEN 'Germany'
        WHEN 'Mercedes'      THEN 'Germany'
        WHEN 'Opel'          THEN 'Germany'
        WHEN 'Porsche'       THEN 'Germany'
        WHEN 'Smart'         THEN 'Germany'
        WHEN 'Volkswagen'    THEN 'Germany'
        -- South Korea
        WHEN 'Daewoo'        THEN 'South Korea'
        WHEN 'Hyundai'       THEN 'South Korea'
        WHEN 'Kgm'           THEN 'South Korea'
        WHEN 'Kia'           THEN 'South Korea'
        WHEN 'Speranza'      THEN 'South Korea'  -- per user: Daewoo-licensed
        WHEN 'Ssang Yong'    THEN 'South Korea'
        -- France
        WHEN 'Bugatti'       THEN 'France'
        WHEN 'Citroën'       THEN 'France'
        WHEN 'Ds'            THEN 'France'
        WHEN 'Peugeot'       THEN 'France'
        WHEN 'Renault'       THEN 'France'
        -- UK
        WHEN 'Aston Martin'  THEN 'UK'
        WHEN 'Bentley'       THEN 'UK'
        WHEN 'Jaguar'        THEN 'UK'
        WHEN 'Land Rover'    THEN 'UK'
        WHEN 'Lotus'         THEN 'UK'
        WHEN 'Mini'          THEN 'UK'
        WHEN 'Rolls Royce'   THEN 'UK'
        -- Spain
        WHEN 'Cupra'         THEN 'Spain'
        WHEN 'Seat'          THEN 'Spain'
        -- Sweden
        WHEN 'Volvo'         THEN 'Sweden'
        -- Czech Republic
        WHEN 'Skoda'         THEN 'Czech Republic'
        -- India
        WHEN 'Mahindra'      THEN 'India'
        WHEN 'Tata'          THEN 'India'
        -- Russia
        WHEN 'Gaz'           THEN 'Russia'
        WHEN 'Lada'          THEN 'Russia'
        -- Iran
        WHEN 'Saipa'         THEN 'Iran'
        -- Malaysia
        WHEN 'Proton'        THEN 'Malaysia'
        ELSE '(Unknown)'  -- (Unknown) sentinel, "Other", and any future brand we haven't classified yet
    END AS origin_country
FROM all_rows
