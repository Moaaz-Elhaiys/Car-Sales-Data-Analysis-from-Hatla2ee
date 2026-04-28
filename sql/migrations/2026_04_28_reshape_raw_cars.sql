-- Idempotent migration: reshape raw.cars from the legacy column set
-- (title/make/class/used_since/body_style/city) to the new field set
-- (external_id/brand/condition/cc/origin_country/assembly_country/release_year/location).
--
-- Safe to run multiple times. Run from psql:
--     \i /sql/migrations/2026_04_28_reshape_raw_cars.sql
-- or via the Makefile target:
--     make migrate

BEGIN;

-- 1. Add the new columns (no-op if they already exist).
ALTER TABLE raw.cars
    ADD COLUMN IF NOT EXISTS external_id      TEXT,
    ADD COLUMN IF NOT EXISTS brand            TEXT,
    ADD COLUMN IF NOT EXISTS condition        TEXT,
    ADD COLUMN IF NOT EXISTS cc               TEXT,
    ADD COLUMN IF NOT EXISTS location         TEXT,
    ADD COLUMN IF NOT EXISTS origin_country   TEXT,
    ADD COLUMN IF NOT EXISTS assembly_country TEXT,
    ADD COLUMN IF NOT EXISTS release_year     TEXT;

-- 2. Backfill renamed columns from their legacy counterparts (only when the
--    legacy column still exists, so this stays safe to re-run).
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='raw' AND table_name='cars' AND column_name='make'
    ) THEN
        UPDATE raw.cars SET brand = make WHERE brand IS NULL AND make IS NOT NULL;
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='raw' AND table_name='cars' AND column_name='city'
    ) THEN
        UPDATE raw.cars SET location = city WHERE location IS NULL AND city IS NOT NULL;
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='raw' AND table_name='cars' AND column_name='used_since'
    ) THEN
        UPDATE raw.cars
           SET release_year = SUBSTRING(used_since FROM '\d{4}')
         WHERE release_year IS NULL AND used_since IS NOT NULL;
    END IF;
END
$$;

-- 3. Backfill external_id from the URL tail.
--    Mirror the spider's EXTERNAL_ID_RE: the id is the trailing /<digits>
--    segment, optionally followed by '/', '?<query>', or '#<fragment>'.
UPDATE raw.cars
   SET external_id = SUBSTRING(link FROM '/(\d+)(?:/|[?#]|$)')
 WHERE external_id IS NULL AND link IS NOT NULL;

-- 4. Drop legacy columns we no longer scrape.
ALTER TABLE raw.cars
    DROP COLUMN IF EXISTS title,
    DROP COLUMN IF EXISTS make,
    DROP COLUMN IF EXISTS class,
    DROP COLUMN IF EXISTS used_since,
    DROP COLUMN IF EXISTS body_style,
    DROP COLUMN IF EXISTS city;

-- 5. Rebuild indexes for the renamed columns.
DROP INDEX IF EXISTS raw.raw_cars_make_idx;
DROP INDEX IF EXISTS raw.raw_cars_city_idx;
CREATE INDEX IF NOT EXISTS raw_cars_brand_idx       ON raw.cars (brand);
CREATE INDEX IF NOT EXISTS raw_cars_location_idx    ON raw.cars (location);
CREATE INDEX IF NOT EXISTS raw_cars_external_id_idx ON raw.cars (external_id);

COMMIT;
