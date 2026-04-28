"""Smoke-test the PostgresPipeline without hitting the live site.

Runs inside the scrapy container, e.g.:
    docker compose run --rm --entrypoint python scrapy scripts/smoke_test_pipeline.py
"""

from __future__ import annotations

import os
import sys
from types import SimpleNamespace

# Make the cars/ package importable when this script is run directly.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from scrapy.utils.project import get_project_settings

from cars.items import CarItem
from cars.pipelines import CleanItemPipeline, PostgresPipeline


def make_item(link: str, external_id: str, **overrides) -> CarItem:
    item = CarItem(
        ExternalId=external_id,
        Link=link,
        Brand="Toyota ",
        Model="Corolla",
        Price="500000",
        Condition="Used",
        Color="White",
        CC="1600",
        Location=" Cairo ",
        OriginCountry="Japan",
        AssemblyCountry="Egypt",
        ReleaseYear="2020",
        Km="120000",
        Transmission="Automatic",
        Fuel="Petrol",
    )
    for k, v in overrides.items():
        item[k] = v
    return item


def main() -> int:
    settings = get_project_settings()
    crawler = SimpleNamespace(settings=settings)

    cleaner = CleanItemPipeline()

    # --- Cleaner assertions (don't touch the DB) ---
    dirty = make_item("https://example.com/clean-check/9001", "9001",
                      Brand="Toyota ", Location=" Cairo ")
    cleaned = cleaner.process_item(dirty, None)
    assert cleaned["Brand"] == "Toyota", \
        f"CleanItemPipeline did not trim Brand: {cleaned['Brand']!r}"
    assert cleaned["Location"] == "Cairo", \
        f"CleanItemPipeline did not trim Location: {cleaned['Location']!r}"

    # --- PostgresPipeline upsert behaviour ---
    # Run two separate "spider sessions" so the upsert lands in a later
    # transaction; otherwise NOW() returns the same value for the INSERT and
    # the conflict-driven UPDATE, and we can't observe updated_at being bumped.
    def run_session(items):
        pg = PostgresPipeline.from_crawler(crawler)
        pg.open_spider(spider=None)
        try:
            for it in items:
                it = cleaner.process_item(it, None)
                pg.process_item(it, None)
        finally:
            pg.close_spider(spider=None)

    run_session([
        make_item("https://example.com/a/9101", "9101"),
        make_item("https://example.com/b/9102", "9102", Brand="Honda", Model="Civic"),
    ])
    run_session([
        # Upsert update: same link, new price.
        make_item("https://example.com/a/9101", "9101", Price="450000"),
    ])

    # Re-open a connection to verify the rows landed.
    pg2 = PostgresPipeline.from_crawler(crawler)
    pg2.open_spider(spider=None)
    try:
        pg2.cur.execute(
            "SELECT link, external_id, brand, model, price, scraped_at, updated_at "
            "FROM raw.cars WHERE link LIKE 'https://example.com/%' ORDER BY id"
        )
        rows = pg2.cur.fetchall()
        print(f"raw.cars now has {len(rows)} matching row(s):")
        for r in rows:
            print(" ", r)

        # Expect 2 rows (a, b) since a was upserted, not duplicated.
        assert len(rows) == 2, f"expected 2 rows after upsert, got {len(rows)}"

        for link, ext_id, _brand, _model, _price, scraped_at, updated_at in rows:
            assert ext_id, f"{link}: external_id missing"
            assert scraped_at is not None, f"{link}: scraped_at is NULL"
            assert updated_at is not None, f"{link}: updated_at is NULL"
            assert updated_at >= scraped_at, (
                f"{link}: updated_at {updated_at!r} precedes scraped_at {scraped_at!r}"
            )

        a_row = next(r for r in rows if r[0] == "https://example.com/a/9101")
        assert a_row[4] == "450000", f"upsert did not update price; got {a_row[4]!r}"
        assert a_row[6] > a_row[5], (
            f"upsert did not bump updated_at: scraped_at={a_row[5]!r} updated_at={a_row[6]!r}"
        )

        b_row = next(r for r in rows if r[0] == "https://example.com/b/9102")
        assert b_row[5] == b_row[6], (
            f"row 'b' was not upserted but updated_at differs from scraped_at: "
            f"scraped_at={b_row[5]!r} updated_at={b_row[6]!r}"
        )

        print(
            "OK: CleanItemPipeline trims whitespace, upsert-by-link works, "
            "external_id is captured, and scraped_at/updated_at behave as expected."
        )
    finally:
        pg2.close_spider(spider=None)
    return 0


if __name__ == "__main__":
    sys.exit(main())
