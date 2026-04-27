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
    pg = PostgresPipeline.from_crawler(crawler)
    pg.open_spider(spider=None)

    try:
        items = [
            make_item("https://example.com/a"),
            make_item("https://example.com/b", Make="Honda", Model="Civic"),
            make_item("https://example.com/a", Price="450000"),  # upsert update
        ]
        for it in items:
            it = cleaner.process_item(it, None)
            pg.process_item(it, None)
    finally:
        pg.close_spider(spider=None)

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
        # Updated row for link 'a' should have price '450000' from the third item.
        a_row = next(r for r in rows if r[0] == "https://example.com/a")
        assert a_row[3] == "450000", f"upsert did not update price; got {a_row[3]!r}"
        print("OK: upsert-by-link works and prices update correctly.")
    finally:
        pg2.close_spider(spider=None)
    return 0


if __name__ == "__main__":
    sys.exit(main())
