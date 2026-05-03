-- Surrogate-id sequence for marts.fact_car_listings.
--
-- The fact table is append-only (no natural-key dedup) so each row needs a
-- unique synthetic id. A single shared sequence keeps spider-driven inserts
-- (the Bruin asset) and historical-CSV inserts (scripts/import_historical_fact.py)
-- in one monotonically-increasing id space without coordinating between them.
--
-- Sequence persists across `make full-refresh` (only the table itself is
-- dropped/recreated by Bruin), so post-rebuild ids never collide with
-- pre-rebuild ones.
--
-- This file is idempotent and safe to re-apply -- it's also picked up via
-- sql/migrations/2026_05_03_fact_surrogate_id.sql for stacks that were
-- created before this file existed.

CREATE SEQUENCE IF NOT EXISTS marts.fact_car_listings_id_seq
    AS BIGINT
    INCREMENT BY 1
    MINVALUE 1
    START WITH 1
    NO CYCLE;

COMMENT ON SEQUENCE marts.fact_car_listings_id_seq IS
    'Surrogate-key generator for marts.fact_car_listings.id. Shared by Bruin and import_historical_fact.py.';
