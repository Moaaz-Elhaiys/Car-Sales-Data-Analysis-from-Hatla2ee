-- Runs automatically on first boot of the postgres container
-- (files in /docker-entrypoint-initdb.d are executed in filename order).

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS marts;

COMMENT ON SCHEMA raw     IS 'Unprocessed scraped data (Scrapy writes here).';
COMMENT ON SCHEMA staging IS 'Cleaned / typed intermediate models (Bruin).';
COMMENT ON SCHEMA marts   IS 'Star-schema dimensions and facts for Power BI.';
