-- raw.cars: append/upsert target for the Scrapy spider.
-- One row per scraped listing (deduped by link). Columns are kept as TEXT here;
-- type casting / cleaning happens later in the staging Bruin asset.
--
-- NOTE: Postgres init scripts only execute on a *fresh* data volume. To apply
-- this on an existing stack, run `make clean && make up` (destroys data) or
-- apply sql/migrations/2026_04_28_reshape_raw_cars.sql via `make migrate`.

CREATE TABLE IF NOT EXISTS raw.cars (
    id               BIGSERIAL    PRIMARY KEY,
    external_id      TEXT,
    link             TEXT         NOT NULL UNIQUE,
    brand            TEXT,
    model            TEXT,
    price            TEXT,
    condition        TEXT,
    color            TEXT,
    cc               TEXT,
    location         TEXT,
    origin_country   TEXT,
    assembly_country TEXT,
    release_year     TEXT,
    km               TEXT,
    transmission     TEXT,
    fuel             TEXT,
    scraped_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS raw_cars_brand_idx       ON raw.cars (brand);
CREATE INDEX IF NOT EXISTS raw_cars_location_idx    ON raw.cars (location);
CREATE INDEX IF NOT EXISTS raw_cars_scraped_at_idx  ON raw.cars (scraped_at);
CREATE INDEX IF NOT EXISTS raw_cars_external_id_idx ON raw.cars (external_id);

COMMENT ON TABLE  raw.cars                  IS 'Raw car listings scraped from hatla2ee. Append/upsert by link.';
COMMENT ON COLUMN raw.cars.external_id      IS 'Numeric id parsed from the tail of the listing URL.';
COMMENT ON COLUMN raw.cars.link             IS 'Source URL for the listing. Natural key.';
COMMENT ON COLUMN raw.cars.scraped_at       IS 'First time this listing was inserted.';
COMMENT ON COLUMN raw.cars.updated_at       IS 'Last time this row was upserted.';
