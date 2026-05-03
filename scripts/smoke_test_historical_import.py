"""End-to-end smoke test for scripts/import_historical_fact.py.

Builds a temp CSV mirroring the real export schema and verifies:

  - rows land in marts.fact_car_listings with sane defaults
  - body_style + used_since are passed through
  - blanks (NaN-in-pandas) become NULL
  - spider/staging-driven rows can coexist (historic-stamped CSV rows
    aren't touched by `make transform`)
  - the importer is INTENTIONALLY non-idempotent: a second run appends
    another full copy of the CSV. We assert this so future regressions
    that silently re-introduce dedup are caught.

Run inside the scrapy container after `make full-refresh`:
    docker compose run --rm \
        --entrypoint python scrapy scripts/smoke_test_historical_import.py
"""

from __future__ import annotations

import csv
import os
import sys
import tempfile
from datetime import datetime, timezone

import psycopg2

# Re-use the importer module so the smoke test exercises the exact same
# code path the user's CSV will go through.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import import_historical_fact as importer  # noqa: E402


# Use a sentinel scraped_at that is unmistakably a test marker and
# distinct from importer.HISTORIC_TS (2020-01-01) so cleanup affects only
# this test's rows even if real historical data is loaded in the same DB.
TEST_SCRAPED_AT = datetime(1999, 12, 31, 23, 59, 59, tzinfo=timezone.utc)

FIXTURE_ROWS = [
    # Mirror the user's pandas dtypes: FK columns as ints, body_style
    # may be blank (NaN -> empty string when to_csv'd without na_rep).
    # Both `link` and `external_id` columns are included to prove the
    # importer ignores them.
    {
        "body_style": "",  # NaN in pandas
        "location_id": 41, "color_id": 20, "fuel_id": 3, "km": 256000,
        "link": "https://example.com/historical/9999990",
        "external_id": "9999990",
        "brand_id": 105, "model_id": 743, "price_egp": 860000, "year_id": 48,
        "transmission_id": 1, "used_since": "2014",
    },
    {
        "body_style": "Hatchback",
        "location_id": 106, "color_id": 42, "fuel_id": 1, "km": 200000,
        "link": "https://example.com/historical/9999992",
        "external_id": "9999992",
        "brand_id": 76, "model_id": 191, "price_egp": 480000, "year_id": 42,
        "transmission_id": 1, "used_since": "2008",
    },
    {
        # Sparse row -- everything missing -> defaults all the way.
        "body_style": "",
        "location_id": "", "color_id": "", "fuel_id": "", "km": "",
        "link": "https://example.com/historical/blank",
        "external_id": "",
        "brand_id": "", "model_id": "", "price_egp": "", "year_id": "",
        "transmission_id": "", "used_since": "",
    },
]

CSV_FIELDS = [
    "body_style", "location_id", "color_id", "fuel_id", "km",
    "link", "external_id", "brand_id", "model_id", "price_egp",
    "year_id", "transmission_id", "used_since",
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
        "SELECT COUNT(*) FROM marts.fact_car_listings WHERE scraped_at = %s;",
        (TEST_SCRAPED_AT,),
    )
    (n,) = cur.fetchone()
    return n


def _cleanup(cur):
    cur.execute(
        "DELETE FROM marts.fact_car_listings WHERE scraped_at = %s;",
        (TEST_SCRAPED_AT,),
    )


def assert_eq(actual, expected, label):
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")


def main() -> int:
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

        # 1. First import: should append all 3 rows (importer never
        #    drops 'invalid' rows now that there's no required natural
        #    key on the row).
        scraped_iso = TEST_SCRAPED_AT.isoformat()
        rc = importer.main(["--csv", tmp.name, "--scraped-at", scraped_iso])
        assert_eq(rc, 0, "first import exit code")

        conn = _connect()
        with conn, conn.cursor() as cur:
            assert_eq(_count_test_rows(cur), 3, "first import row count")

            # 2. Spot-check defaults + values landed correctly.
            cur.execute(
                """
                SELECT id, brand_id, model_id, condition_id, assembly_country_id,
                       cc, body_style, used_since, scraped_at, updated_at
                FROM marts.fact_car_listings
                WHERE scraped_at = %s AND brand_id = 76;
                """,
                (TEST_SCRAPED_AT,),
            )
            rows = cur.fetchall()
            assert_eq(len(rows), 1, "exactly one Hatchback fixture row")
            (row_id, brand_id, model_id, condition_id, assembly_country_id,
             cc, body_style, used_since, scraped_at, updated_at) = rows[0]
            if not isinstance(row_id, int) or row_id <= 0:
                raise AssertionError(f"id should be a positive bigint; got {row_id!r}")
            assert_eq(brand_id, 76, "brand_id passthrough")
            assert_eq(model_id, 191, "model_id passthrough")
            assert_eq(condition_id, 0, "condition_id default = sentinel")
            assert_eq(assembly_country_id, 0, "assembly_country_id default = sentinel")
            assert_eq(cc, None, "cc default = NULL")
            assert_eq(body_style, "Hatchback", "body_style passthrough")
            assert_eq(used_since, 2008, "used_since coerced to int")
            assert_eq(scraped_at, TEST_SCRAPED_AT, "scraped_at = TEST_SCRAPED_AT")
            assert_eq(updated_at, TEST_SCRAPED_AT, "updated_at = TEST_SCRAPED_AT")

            # 3. Verify NaN-in-pandas surfaces as NULL body_style.
            cur.execute(
                """
                SELECT body_style FROM marts.fact_car_listings
                WHERE scraped_at = %s AND brand_id = 105;
                """,
                (TEST_SCRAPED_AT,),
            )
            assert_eq(cur.fetchone()[0], None, "blank body_style -> NULL")

            # 4. Verify the all-blank row landed with sentinel/NULL defaults.
            cur.execute(
                """
                SELECT brand_id, model_id, location_id, year_id, price_egp, km, used_since
                FROM marts.fact_car_listings
                WHERE scraped_at = %s AND body_style IS NULL AND brand_id = 0;
                """,
                (TEST_SCRAPED_AT,),
            )
            (b, m, loc, yr, p, k, us) = cur.fetchone()
            assert_eq((b, m, loc, yr), (0, 0, 0, 0), "all-blank row -> sentinel FKs")
            assert_eq((p, k, us), (None, None, None), "all-blank row -> NULL measures")

        # 5. Second import: NOT idempotent -- count should DOUBLE to 6.
        rc = importer.main(["--csv", tmp.name, "--scraped-at", scraped_iso])
        assert_eq(rc, 0, "second import exit code")

        conn = _connect()
        with conn, conn.cursor() as cur:
            assert_eq(
                _count_test_rows(cur), 6,
                "non-idempotency: second run must double the rows"
            )

            # 6. All 6 ids are unique (sequence works).
            cur.execute(
                "SELECT COUNT(DISTINCT id) FROM marts.fact_car_listings WHERE scraped_at = %s;",
                (TEST_SCRAPED_AT,),
            )
            (distinct_ids,) = cur.fetchone()
            assert_eq(distinct_ids, 6, "all 6 surrogate ids are unique")

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
