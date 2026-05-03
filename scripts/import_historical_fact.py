"""One-shot importer that appends historical fact rows from a CSV.

Run inside the scrapy container after `make full-refresh` has built the
fact table:

    docker compose run --rm \
        --entrypoint python \
        -v $$PWD/data:/app/data \
        scrapy scripts/import_historical_fact.py \
        --csv data/historical_fact.csv

Or via the Makefile shortcut: `make import-historical CSV=data/historical_fact.csv`.

The CSV is expected to carry pre-resolved dim FKs (brand_id, model_id,
location_id, ...) that already line up with the current marts.dim_*
tables. Columns recognised:

    external_id       (REQUIRED, natural key, numeric -- listing id from
                       the tail of the hatla2ee URL)
    brand_id, model_id, color_id, fuel_id, transmission_id,
    location_id, year_id
    price_egp, km
    body_style          (text, nullable)
    used_since          (year, nullable, e.g. "2014")

The `link` column may also be present in the CSV -- it is silently
ignored. external_id is the natural identity of a listing on hatla2ee
(URLs can change, the numeric id doesn't), so the fact table keys on
external_id alone.

Anything else in the CSV is silently ignored. Missing columns are
filled with sensible defaults:

    condition_id, assembly_country_id  -> 0  (sentinel '(Unknown)' row)
    cc                                  -> NULL
    scraped_at, updated_at              -> 2020-01-01 UTC (HISTORIC_TS)
                                           -- well outside any normal
                                           -- incremental sweep window so
                                           -- `make transform` won't try
                                           -- to re-merge them.

Idempotent: dedupes via `WHERE NOT EXISTS` on external_id. Re-running
the script after `make full-refresh` (which wipes the fact table)
restores the same set of historical rows.
"""

from __future__ import annotations

import argparse
import csv
import os
import sys
from datetime import datetime, timezone
from typing import Any

import psycopg2

# Anchor historical rows well before any realistic spider sweep window so
# `make transform` (which filters staging.cars by updated_at over the last
# N days) never tries to re-merge them.
HISTORIC_TS = datetime(2020, 1, 1, tzinfo=timezone.utc)

# Bruin's merge strategy doesn't create a UNIQUE constraint on the natural
# key (the `unique` quality check is a SELECT-time validation, not a DB
# constraint). Use NOT EXISTS for application-level dedup so we don't
# depend on a constraint that may not be there.
INSERT_SQL = """
INSERT INTO marts.fact_car_listings (
    external_id,
    brand_id, model_id, condition_id, color_id, fuel_id,
    transmission_id, location_id, assembly_country_id, year_id,
    price_egp, km, cc,
    body_style, used_since,
    scraped_at, updated_at
)
SELECT
    %(external_id)s,
    %(brand_id)s, %(model_id)s, %(condition_id)s, %(color_id)s, %(fuel_id)s,
    %(transmission_id)s, %(location_id)s, %(assembly_country_id)s, %(year_id)s,
    %(price_egp)s, %(km)s, %(cc)s,
    %(body_style)s, %(used_since)s,
    %(scraped_at)s, %(updated_at)s
WHERE NOT EXISTS (
    SELECT 1 FROM marts.fact_car_listings WHERE external_id = %(external_id)s
);
"""


def _clean(val: Any) -> str | None:
    """Return a stripped string or None for blanks / pandas NaN markers."""
    if val is None:
        return None
    s = str(val).strip()
    if not s or s.lower() in {"nan", "none", "null", "n/a", "na"}:
        return None
    return s


def _to_int(val: Any) -> int | None:
    """Coerce to int; CSVs often store integer columns as floats ('3.0')."""
    s = _clean(val)
    if s is None:
        return None
    try:
        return int(float(s))
    except ValueError:
        return None


def _to_int_default(val: Any, default: int) -> int:
    """Like `_to_int` but falls back to `default` on missing/invalid input."""
    parsed = _to_int(val)
    return parsed if parsed is not None else default


def build_row(raw: dict[str, Any]) -> dict[str, Any] | None:
    """Map one CSV record to fact_car_listings parameters. Returns None if invalid.

    A row is invalid if external_id is missing or non-numeric -- it's the
    not-null PK of the fact table, so we can't insert without it.

    Any `link` column in the CSV is silently dropped -- the fact table no
    longer carries it; external_id is the only natural key.
    """
    external_id = _to_int(raw.get("external_id"))
    if external_id is None:
        return None
    return {
        "external_id":         external_id,
        # FK columns: default to sentinel id=0 if missing/garbled so the
        # not_null quality checks on the fact table never fire.
        "brand_id":            _to_int_default(raw.get("brand_id"),            0),
        "model_id":            _to_int_default(raw.get("model_id"),            0),
        "condition_id":        _to_int_default(raw.get("condition_id"),        0),
        "color_id":            _to_int_default(raw.get("color_id"),            0),
        "fuel_id":             _to_int_default(raw.get("fuel_id"),             0),
        "transmission_id":     _to_int_default(raw.get("transmission_id"),     0),
        "location_id":         _to_int_default(raw.get("location_id"),         0),
        "assembly_country_id": _to_int_default(raw.get("assembly_country_id"), 0),
        "year_id":             _to_int_default(raw.get("year_id"),             0),
        # Measures: NULL is fine (non_negative check is skipped on NULL).
        "price_egp":           _to_int(raw.get("price_egp")),
        "km":                  _to_int(raw.get("km")),
        "cc":                  _to_int(raw.get("cc")),
        # Historical-only columns.
        "body_style":          _clean(raw.get("body_style")),
        "used_since":          _to_int(raw.get("used_since")),
        # Anchor timestamps so incremental runs ignore these rows.
        "scraped_at":          HISTORIC_TS,
        "updated_at":          HISTORIC_TS,
    }


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--csv", required=True, help="Path to the historical fact CSV.")
    ap.add_argument(
        "--dry-run",
        action="store_true",
        help="Parse and validate the CSV without touching the database.",
    )
    args = ap.parse_args(argv)

    if not os.path.exists(args.csv):
        sys.stderr.write(f"CSV not found: {args.csv}\n")
        return 2

    parsed: list[dict[str, Any]] = []
    skipped_blank = 0
    with open(args.csv, newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        for raw in reader:
            row = build_row(raw)
            if row is None:
                skipped_blank += 1
                continue
            parsed.append(row)

    print(
        f"Parsed {len(parsed)} candidate rows from {args.csv}"
        f" (skipped {skipped_blank} with missing/non-numeric external_id).",
        flush=True,
    )

    if args.dry_run:
        print("--dry-run: skipping database insert.")
        return 0

    if not parsed:
        print("Nothing to insert.")
        return 0

    conn = psycopg2.connect(
        host=os.getenv("POSTGRES_HOST", "postgres"),
        port=int(os.getenv("POSTGRES_PORT", 5432)),
        dbname=os.getenv("POSTGRES_DB", "cars"),
        user=os.getenv("POSTGRES_USER", "cars"),
        password=os.getenv("POSTGRES_PASSWORD", "cars"),
    )
    try:
        inserted = 0
        with conn, conn.cursor() as cur:
            for row in parsed:
                cur.execute(INSERT_SQL, row)
                inserted += cur.rowcount
            cur.execute("SELECT COUNT(*) FROM marts.fact_car_listings;")
            (total,) = cur.fetchone()
    finally:
        conn.close()

    skipped_existing = len(parsed) - inserted
    print(
        f"Inserted {inserted} new rows;"
        f" skipped {skipped_existing} that already existed."
        f" marts.fact_car_listings now holds {total} rows."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
