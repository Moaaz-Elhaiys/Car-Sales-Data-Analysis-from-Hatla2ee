-- Migration: switch marts.fact_car_listings to a surrogate id PK.
--
-- Apply via `make migrate` against any stack that was built before
-- sql/init/03_fact_car_listings_seq.sql existed. Idempotent.
--
-- Run order:
--   1. This migration creates the shared sequence.
--   2. Re-run `make full-refresh` -- Bruin drops + rebuilds fact_car_listings
--      with the new schema (id PK, no external_id, no link).
--   3. Re-run `make import-historical` to repopulate historical rows.

CREATE SCHEMA IF NOT EXISTS marts;

CREATE SEQUENCE IF NOT EXISTS marts.fact_car_listings_id_seq
    AS BIGINT
    INCREMENT BY 1
    MINVALUE 1
    START WITH 1
    NO CYCLE;

COMMENT ON SEQUENCE marts.fact_car_listings_id_seq IS
    'Surrogate-key generator for marts.fact_car_listings.id. Shared by Bruin and import_historical_fact.py.';
