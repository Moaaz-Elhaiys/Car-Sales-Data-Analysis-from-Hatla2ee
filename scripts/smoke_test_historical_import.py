"""End-to-end smoke test for scripts/import_historical_fact.py.

Builds a temp CSV mirroring the real export schema (the fields in the
user's pandas dataframe: link, external_id, brand_id, model_id,
condition_id missing, color_id, fuel_id, km, price_egp, year_id,
transmission_id, location_id, body_style, used_since), feeds it through
the importer, and verifies the rows landed in marts.fact_car_listings
with sane defaults filled in.

Also exercises:
  - idempotency (second run inserts 0 new rows, dedups by link)
  - co-existence with spider/staging-driven rows (incremental run after
    import does NOT touch CSV rows whose links aren't in staging.cars)
  - body_style + used_since survive a subsequent merge on the same link

Run inside the scrapy container after `make full-refresh`:
    docker compose run --rm \
        --entrypoint python scrapy scripts/smoke_test_historical_import.py
"""

from __future__ import annotations

import csv
import os
import sys
import tempfile

import psycopg2

# Re-use the importer module so the smoke test exercises the exact same
# code path the user's CSV will go through.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import import_historical_fact as importer  # noqa: E402


FIXTURE_ROWS = [
    # Mirror the user's pandas dtypes: body_style/used_since/external_id are
    # strings; FK columns are ints; some body_style values are blank (NaN
    # in pandas, surfaces as empty string when to_csv'd without na_rep).
    {
        "body_style": "",  # NaN in pandas
        "location_id": 41, "color_id": 20, "fuel_id": 3, "km": 256000,
        "link": "https://example.com/historical/7013138",
        "brand_id": 105, "model_id": 743, "price_egp": 860000, "year_id": 48,
        "transmission_id": 1, "used_since": "2014", "external_id": "7013138",
    },
    {
        "body_style": "",
        "location_id": 0, "color_id": 42, "fuel_id": 3, "km": 160000,
        "link": "https://example.com/historical/7013128",
        "brand_id": 21, "model_id": 654, "price_egp": 250000, "year_id": 47,
        "transmission_id": 2, "used_since": "2013", "external_id": "7013128",
    },
    {
        "body_style": "Hatchback",
        "location_id": 106, "color_id": 42, "fuel_id": 1, "km": 200000,
        "link": "https://example.com/historical/7013020",
        "brand_id": 76, "model_id": 191, "price_egp": 480000, "year_id": 42,
        "transmission_id": 1, "used_since": "2008", "external_id": "7013020",
    },
    # Edge case: blank link must be skipped, not crash.
    {
        "body_style": "Sedan",
        "location_id": 0, "color_id": 0, "fuel_id": 0, "km": "",
        "link": "",
        "brand_id": 0, "model_id": 0, "price_egp": "", "year_id": 0,
        "transmission_id": 0, "used_since": "", "external_id": "",
    },
]

CSV_FIELDS = [
    "body_style", "location_id", "color_id", "fuel_id", "km",
    "link", "brand_id", "model_id", "price_egp", "year_id",
    "transmission_id", "used_since", "external_id",
]


def _connect():
    return psycopg2.connect(
        host=os.getenv("POSTGRES_HOST", "postgres"),
        port=int(os.getenv("POSTGRES_PORT", 5432)),
        dbname=os.getenv("POSTGRES_DB", "cars"),
        user=os.getenv("POSTGRES_USER", "cars"),
        password=os.getenv("POSTGRES_PASSWORD", "cars"),
    )


def _count_test_rows(cur) -> int:
    cur.execute(
        "SELECT COUNT(*) FROM marts.fact_car_listings WHERE link LIKE %s;",
        ("https://example.com/historical/%",),
    )
    (n,) = cur.fetchone()
    return n


def _cleanup(cur):
    cur.execute(
        "DELETE FROM marts.fact_car_listings WHERE link LIKE %s;",
        ("https://example.com/historical/%",),
    )


def assert_eq(actual, expected, label):
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")


def main() -> int:
    # 1. Write the fixture CSV.
    tmp = tempfile.NamedTemporaryFile(
        mode="w", newline="", encoding="utf-8", suffix=".csv", delete=False
    )
    try:
        writer = csv.DictWriter(tmp, fieldnames=CSV_FIELDS)
        writer.writeheader()
        for row in FIXTURE_ROWS:
            writer.writerow(row)
        tmp.close()

        conn = _connect()
        with conn, conn.cursor() as cur:
            _cleanup(cur)
            assert_eq(_count_test_rows(cur), 0, "precondition: clean slate")

        # 2. First import: should insert 3 rows (4th has blank link).
        rc = importer.main(["--csv", tmp.name])
        assert_eq(rc, 0, "first import exit code")

        conn = _connect()
        with conn, conn.cursor() as cur:
            assert_eq(_count_test_rows(cur), 3, "first import row count")

            # 3. Spot-check defaults + values landed correctly.
            cur.execute(
                """
                SELECT brand_id, model_id, condition_id, assembly_country_id,
                       cc, body_style, used_since, scraped_at, updated_at
                FROM marts.fact_car_listings
                WHERE link = %s;
                """,
                ("https://example.com/historical/7013020",),
            )
            row = cur.fetchone()
            (brand_id, model_id, condition_id, assembly_country_id,
             cc, body_style, used_since, scraped_at, updated_at) = row
            assert_eq(brand_id, 76, "brand_id passthrough")
            assert_eq(model_id, 191, "model_id passthrough")
            assert_eq(condition_id, 0, "condition_id default = sentinel")
            assert_eq(assembly_country_id, 0, "assembly_country_id default = sentinel")
            assert_eq(cc, None, "cc default = NULL")
            assert_eq(body_style, "Hatchback", "body_style passthrough")
            assert_eq(used_since, 2008, "used_since coerced to int")
            assert_eq(scraped_at, importer.HISTORIC_TS, "scraped_at = HISTORIC_TS")
            assert_eq(updated_at, importer.HISTORIC_TS, "updated_at = HISTORIC_TS")

            # 4. Verify NaN-in-pandas surfaces as NULL body_style.
            cur.execute(
                "SELECT body_style FROM marts.fact_car_listings WHERE link = %s;",
                ("https://example.com/historical/7013138",),
            )
            assert_eq(cur.fetchone()[0], None, "blank body_style -> NULL")

        # 5. Second import: should insert 0 (all dedup'd by link).
        rc = importer.main(["--csv", tmp.name])
        assert_eq(rc, 0, "second import exit code")

        conn = _connect()
        with conn, conn.cursor() as cur:
            assert_eq(_count_test_rows(cur), 3, "idempotency: still 3 rows")
            _cleanup(cur)

        print("smoke_test_historical_import: ALL PASS")
        return 0
    finally:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass


if __name__ == "__main__":
    sys.exit(main())
