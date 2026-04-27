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


def make_item(link: str, **overrides) -> CarItem:
    item = CarItem(
        Title="Test car listing",
        Price="500000",
        Make="Toyota ",
        Model="Corolla",
        Fuel="Petrol",
        Transmission="Automatic",
        Color="White",
        Class="Sedan",
        Km="120000",
        Used_since="2020",
        Body_style="Sedan",
        City="Cairo",
        Link=link,
    )
    for k, v in overrides.items():
        item[k] = v
    return item


def main() -> int:
    settings = get_project_settings()
    crawler = SimpleNamespace(settings=settings)

    cleaner = CleanItemPipeline()

    # --- Cleaner assertions (don't touch the DB) ---
    dirty = make_item("https://example.com/clean-check", Make="Toyota ", City=" Cairo ")
    cleaned = cleaner.process_item(dirty, None)
    assert cleaned["Make"] == "Toyota", f"CleanItemPipeline did not trim Make: {cleaned['Make']!r}"
    assert cleaned["City"] == "Cairo", f"CleanItemPipeline did not trim City: {cleaned['City']!r}"

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
        make_item("https://example.com/a"),
        make_item("https://example.com/b", Make="Honda", Model="Civic"),
    ])
    run_session([
        make_item("https://example.com/a", Price="450000"),  # upsert update
    ])

    # Re-open a connection to verify the rows landed.
    pg2 = PostgresPipeline.from_crawler(crawler)
    pg2.open_spider(spider=None)
    try:
        pg2.cur.execute(
            "SELECT link, make, model, price, scraped_at, updated_at "
            "FROM raw.cars ORDER BY id"
        )
        rows = pg2.cur.fetchall()
        print(f"raw.cars now has {len(rows)} row(s):")
        for r in rows:
            print(" ", r)

        # Expect 2 rows (a, b) since a was upserted, not duplicated.
        assert len(rows) == 2, f"expected 2 rows after upsert, got {len(rows)}"

        # Per-row temporal sanity: scraped_at and updated_at are non-null and
        # updated_at is never before scraped_at.
        for link, _make, _model, _price, scraped_at, updated_at in rows:
            assert scraped_at is not None, f"{link}: scraped_at is NULL"
            assert updated_at is not None, f"{link}: updated_at is NULL"
            assert updated_at >= scraped_at, (
                f"{link}: updated_at {updated_at!r} precedes scraped_at {scraped_at!r}"
            )

        # Updated row for link 'a' should have price '450000' from the third item,
        # AND its updated_at should be strictly after its scraped_at (the upsert
        # bumps updated_at via NOW()).
        a_row = next(r for r in rows if r[0] == "https://example.com/a")
        assert a_row[3] == "450000", f"upsert did not update price; got {a_row[3]!r}"
        assert a_row[5] > a_row[4], (
            f"upsert did not bump updated_at: scraped_at={a_row[4]!r} updated_at={a_row[5]!r}"
        )

        # Row 'b' was inserted once and not re-upserted, so timestamps should match.
        b_row = next(r for r in rows if r[0] == "https://example.com/b")
        assert b_row[4] == b_row[5], (
            f"row 'b' was not upserted but updated_at differs from scraped_at: "
            f"scraped_at={b_row[4]!r} updated_at={b_row[5]!r}"
        )

        print(
            "OK: CleanItemPipeline trims whitespace, upsert-by-link works, "
            "and scraped_at/updated_at behave as expected."
        )
    finally:
        pg2.close_spider(spider=None)
    return 0


if __name__ == "__main__":
    sys.exit(main())
