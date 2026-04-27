-- raw.cars: append/upsert target for the Scrapy spider.
-- One row per scraped listing (deduped by link). Columns are kept as TEXT here;
-- type casting / cleaning happens later in the staging Bruin asset.

CREATE TABLE IF NOT EXISTS raw.cars (
    id           BIGSERIAL    PRIMARY KEY,
    link         TEXT         NOT NULL UNIQUE,
    title        TEXT,
    price        TEXT,
    make         TEXT,
    model        TEXT,
    fuel         TEXT,
    transmission TEXT,
    color        TEXT,
    class        TEXT,
    km           TEXT,
    used_since   TEXT,
    body_style   TEXT,
    city         TEXT,
    scraped_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS raw_cars_make_idx       ON raw.cars (make);
CREATE INDEX IF NOT EXISTS raw_cars_city_idx       ON raw.cars (city);
CREATE INDEX IF NOT EXISTS raw_cars_scraped_at_idx ON raw.cars (scraped_at);

COMMENT ON TABLE  raw.cars              IS 'Raw car listings scraped from hatla2ee. Append/upsert by link.';
COMMENT ON COLUMN raw.cars.link         IS 'Source URL for the listing. Natural key.';
COMMENT ON COLUMN raw.cars.scraped_at   IS 'First time this listing was inserted.';
COMMENT ON COLUMN raw.cars.updated_at   IS 'Last time this row was upserted.';
