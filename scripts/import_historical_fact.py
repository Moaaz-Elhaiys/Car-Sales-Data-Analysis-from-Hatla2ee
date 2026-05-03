"""Append historical fact rows from a CSV onto marts.fact_car_listings.

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

    brand_id, model_id, color_id, fuel_id, transmission_id,
    location_id, year_id
    price_egp, km
    body_style          (text, nullable)
    used_since          (year, nullable, e.g. "2014")

Any `link` or `external_id` column in the CSV is silently ignored --
the fact table no longer carries either; rows are identified only by
the surrogate `id` column generated from
marts.fact_car_listings_id_seq.

Anything else in the CSV is silently ignored. Missing columns are
filled with sensible defaults:

    condition_id, assembly_country_id  -> 0  (sentinel '(Unknown)' row)
    cc                                  -> NULL
    scraped_at, updated_at              -> 2020-01-01 UTC (HISTORIC_TS)
                                           -- well outside any normal
                                           -- incremental sweep window so
                                           -- `make transform` won't try
                                           -- to touch them.

NOT IDEMPOTENT. Re-running this script appends another full copy of
the CSV. If you want to re-import, first run:

    docker compose exec postgres psql -U cars -d cars \
        -c "TRUNCATE marts.fact_car_listings;"

(or rebuild the table with `make full-refresh`).
"""

from __future__ import annotations

import argparse
import csv
import os
import sys
from datetime import datetime, timezone
from typing import Any

import psycopg2
from psycopg2.extras import execute_values

# Anchor historical rows well before any realistic spider sweep window so
# `make transform` (which filters staging.cars by updated_at over the last
# N days) never picks them up.
HISTORIC_TS = datetime(2020, 1, 1, tzinfo=timezone.utc)

# Single batch INSERT using nextval() per row so spider-driven inserts
# (the Bruin asset, also using nextval on the same sequence) and historical
# inserts share one monotonic id space without coordinating.
INSERT_SQL = """
INSERT INTO marts.fact_car_listings (
    id,
    brand_id, model_id, condition_id, color_id, fuel_id,
    transmission_id, location_id, assembly_country_id, year_id,
    price_egp, km, cc,
    body_style, used_since,
    scraped_at, updated_at
)
SELECT
    nextval('marts.fact_car_listings_id_seq'),
    v.brand_id::BIGINT, v.model_id::BIGINT, v.condition_id::BIGINT,
    v.color_id::BIGINT, v.fuel_id::BIGINT, v.transmission_id::BIGINT,
    v.location_id::BIGINT, v.assembly_country_id::BIGINT, v.year_id::BIGINT,
    v.price_egp::BIGINT, v.km::INTEGER, v.cc::INTEGER,
    v.body_style::TEXT, v.used_since::INTEGER,
    v.scraped_at::TIMESTAMPTZ, v.updated_at::TIMESTAMPTZ
FROM (VALUES %s) AS v(
    brand_id, model_id, condition_id, color_id, fuel_id,
    transmission_id, location_id, assembly_country_id, year_id,
    price_egp, km, cc,
    body_style, used_since,
    scraped_at, updated_at
);
"""

# Order of values in each tuple must match the (VALUES %s) column list above.
ROW_KEYS = (
    "brand_id", "model_id", "condition_id", "color_id", "fuel_id",
    "transmission_id", "location_id", "assembly_country_id", "year_id",
    "price_egp", "km", "cc",
    "body_style", "used_since",
    "scraped_at", "updated_at",
)


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


def build_row(raw: dict[str, Any], scraped_at: datetime = HISTORIC_TS) -> dict[str, Any]:
    """Map one CSV record to fact_car_listings parameters.

    Returns a dict with the fact-table columns; never None (since the
    fact is append-only with a surrogate id, no row can be 'invalid'
    beyond what the dim/measure defaults already cover).

    Any `link` or `external_id` column in the CSV is silently dropped --
    the fact table no longer carries either.
    """
    return {
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
        "scraped_at":          scraped_at,
        "updated_at":          scraped_at,
    }


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--csv", required=True, help="Path to the historical fact CSV.")
    ap.add_argument(
        "--dry-run",
        action="store_true",
        help="Parse and validate the CSV without touching the database.",
    )
    ap.add_argument(
        "--scraped-at",
        default=None,
        help=(
            "ISO timestamp to stamp on every row's scraped_at/updated_at."
            " Defaults to 2020-01-01 UTC (well outside any incremental"
            " sweep). Mostly useful for tests."
        ),
    )
    args = ap.parse_args(argv)

    if not os.path.exists(args.csv):
        sys.stderr.write(f"CSV not found: {args.csv}\n")
        return 2

    if args.scraped_at:
        try:
            scraped_at = datetime.fromisoformat(args.scraped_at)
            if scraped_at.tzinfo is None:
                scraped_at = scraped_at.replace(tzinfo=timezone.utc)
        except ValueError:
            sys.stderr.write(f"Invalid --scraped-at: {args.scraped_at!r}\n")
            return 2
    else:
        scraped_at = HISTORIC_TS

    sys.stderr.write(
        "WARNING: import_historical_fact.py is NOT idempotent. Each run"
        " appends another full copy of the CSV. To re-import, first"
        " TRUNCATE marts.fact_car_listings (or run `make full-refresh`).\n"
    )
    sys.stderr.flush()

    parsed: list[dict[str, Any]] = []
    with open(args.csv, newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        for raw in reader:
            parsed.append(build_row(raw, scraped_at=scraped_at))

    print(f"Parsed {len(parsed)} rows from {args.csv}.", flush=True)

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
        with conn, conn.cursor() as cur:
            tuples = [tuple(row[k] for k in ROW_KEYS) for row in parsed]
            execute_values(cur, INSERT_SQL, tuples, page_size=1000)
            inserted = cur.rowcount  # not always reliable across drivers; treat as best-effort
            cur.execute("SELECT COUNT(*) FROM marts.fact_car_listings;")
            (total,) = cur.fetchone()
    finally:
        conn.close()

    # `inserted` is best-effort; we always processed len(parsed) input rows.
    print(
        f"Appended {len(parsed)} rows."
        f" marts.fact_car_listings now holds {total} rows."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
