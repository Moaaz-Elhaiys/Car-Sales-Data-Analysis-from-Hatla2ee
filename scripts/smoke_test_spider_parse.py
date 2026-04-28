"""Offline smoke-test for CarsSpider.parse_car_page.

Builds a synthetic HtmlResponse that mimics the new hatla2ee detail-page DOM
(brand/model/condition/colour/CC/location/origin/assembly + price + top chips)
and asserts every CarItem field is populated correctly. No network needed --
runs anywhere Scrapy is installed.

    docker compose run --rm --entrypoint python scrapy scripts/smoke_test_spider_parse.py
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from scrapy.http import HtmlResponse, Request

from cars.spiders.cars_spider import CarsSpider


SAMPLE_HTML = """
<html><body>
  <h1>Mercedes GLE 2026 A/T / GLE 53 4MATIC+ For Sale</h1>

  <div id="listing-overview">
    <div class="flex flex-col gap-1 md:items-end">
      <span class="inline-flex items-baseline text-2xl text-primary-800">
        <span class="leading-none font-bold">8,600,000</span>
        <span class="leading-none ms-1 font-bold text-primary-800">EGP</span>
      </span>
    </div>
  </div>

  <!-- Top chips: year / km / transmission / fuel (no textual labels, only icons) -->
  <div class="flex items-center gap-1 bg-gray-50 px-4 py-1.5 rounded-md text-xs">
    <div class="shrink-0">[icon]</div>
    <div class="flex flex-col w-full">
      <span class="rtl:text-right font-medium text-xs lg:text-sm">2026</span>
    </div>
  </div>
  <div class="flex items-center gap-1 bg-gray-50 px-4 py-1.5 rounded-md text-xs">
    <div class="shrink-0">[icon]</div>
    <div class="flex flex-col w-full">
      <span class="rtl:text-right font-medium text-xs lg:text-sm">0 KM</span>
    </div>
  </div>
  <div class="flex items-center gap-1 bg-gray-50 px-4 py-1.5 rounded-md text-xs">
    <div class="shrink-0">[icon]</div>
    <div class="flex flex-col w-full">
      <span class="rtl:text-right font-medium text-xs lg:text-sm">Automatic</span>
    </div>
  </div>
  <div class="flex items-center gap-1 bg-gray-50 px-4 py-1.5 rounded-md text-xs">
    <div class="shrink-0">[icon]</div>
    <div class="flex flex-col w-full">
      <span class="rtl:text-right font-medium text-xs lg:text-sm">Gas</span>
    </div>
  </div>

  <!-- Car Details panel: each row is a label div + value div sibling -->
  <div class="grid gap-6 text-xs md:text-sm md:grid-cols-2">
    <div>
      <div class="flex -mt-[1px]">
        <div class="text-muted-foreground border border-gray-50 bg-primary-50 py-2 px-3 w-full flex items-center">Brand</div>
        <div class="font-medium border border-gray-100 py-2 px-3 w-full flex items-center">Mercedes</div>
      </div>
      <div class="flex -mt-[1px]">
        <div class="text-muted-foreground border border-gray-50 bg-primary-50 py-2 px-3 w-full flex items-center">Model</div>
        <div class="font-medium border border-gray-100 py-2 px-3 w-full flex items-center">GLE</div>
      </div>
      <div class="flex -mt-[1px]">
        <div class="text-muted-foreground border border-gray-50 bg-primary-50 py-2 px-3 w-full flex items-center">Class</div>
        <div class="font-medium border border-gray-100 py-2 px-3 w-full flex items-center">A/T / GLE 53 4MATIC+</div>
      </div>
      <div class="flex -mt-[1px]">
        <div class="text-muted-foreground border border-gray-50 bg-primary-50 py-2 px-3 w-full flex items-center">Condition</div>
        <div class="font-medium border border-gray-100 py-2 px-3 w-full flex items-center">New</div>
      </div>
      <div class="flex -mt-[1px]">
        <div class="text-muted-foreground border border-gray-50 bg-primary-50 py-2 px-3 w-full flex items-center">Color</div>
        <div class="font-medium border border-gray-100 py-2 px-3 w-full flex items-center">Black</div>
      </div>
      <div class="flex -mt-[1px]">
        <div class="text-muted-foreground border border-gray-50 bg-primary-50 py-2 px-3 w-full flex items-center">CC</div>
        <div class="font-medium border border-gray-100 py-2 px-3 w-full flex items-center">3000</div>
      </div>
    </div>
    <div>
      <div class="flex -mt-[1px]">
        <div class="text-muted-foreground border border-gray-50 bg-primary-50 py-2 px-3 w-full flex items-center">Posted On</div>
        <div class="font-medium border border-gray-100 py-2 px-3 w-full flex items-center">2026-04-28</div>
      </div>
      <div class="flex -mt-[1px]">
        <div class="text-muted-foreground border border-gray-50 bg-primary-50 py-2 px-3 w-full flex items-center">Last Updated</div>
        <div class="font-medium border border-gray-100 py-2 px-3 w-full flex items-center">2026-04-28</div>
      </div>
      <div class="flex -mt-[1px]">
        <div class="text-muted-foreground border border-gray-50 bg-primary-50 py-2 px-3 w-full flex items-center">Location</div>
        <div class="font-medium border border-gray-100 py-2 px-3 w-full flex items-center">Cairo</div>
      </div>
      <div class="flex -mt-[1px]">
        <div class="text-muted-foreground border border-gray-50 bg-primary-50 py-2 px-3 w-full flex items-center">Assembly Country</div>
        <div class="font-medium border border-gray-100 py-2 px-3 w-full flex items-center"><a href="#">Germany</a></div>
      </div>
      <div class="flex -mt-[1px]">
        <div class="text-muted-foreground border border-gray-50 bg-primary-50 py-2 px-3 w-full flex items-center">Origin Country</div>
        <div class="font-medium border border-gray-100 py-2 px-3 w-full flex items-center"><a href="#">Germany</a></div>
      </div>
    </div>
  </div>
</body></html>
"""


def main() -> int:
    url = "https://eg.hatla2ee.com/en/car/mercedes/gle/123456"
    request = Request(url)
    response = HtmlResponse(
        url=url,
        body=SAMPLE_HTML.encode("utf-8"),
        encoding="utf-8",
        request=request,
    )

    spider = CarsSpider()
    items = list(spider.parse_car_page(response))
    assert len(items) == 1, f"expected 1 item, got {len(items)}"
    item = items[0]

    expected = {
        "ExternalId": "123456",
        "Link": url,
        "Brand": "Mercedes",
        "Model": "GLE",
        "Price": "8600000",
        "Condition": "New",
        "Color": "Black",
        "CC": "3000",
        "Location": "Cairo",
        "OriginCountry": "Germany",
        "AssemblyCountry": "Germany",
        "ReleaseYear": "2026",
        "Km": "0",
        "Transmission": "Automatic",
        "Fuel": "Gas",
    }
    for field, want in expected.items():
        got = item.get(field)
        assert got == want, f"{field}: expected {want!r}, got {got!r}"

    print("OK: parse_car_page extracted all 15 fields correctly.")
    print("  ", dict(item))

    # --- Bonus: classifier resilience checks ---
    from cars.spiders.cars_spider import _classify_chip
    classifier_cases = [
        ("2026",                  "year"),
        ("0 KM",                  "km"),
        ("120,000 km",            "km"),
        ("Automatic",             "transmission"),
        ("Automatic Transmission", "transmission"),  # copy variation
        ("MANUAL",                "transmission"),
        ("Gas",                   "fuel"),
        ("Diesel Engine",         "fuel"),            # copy variation
        ("Some new chip",         None),              # unknown -> dropped
    ]
    for value, want in classifier_cases:
        got = _classify_chip(value)
        assert got == want, f"_classify_chip({value!r}) -> {got!r}, expected {want!r}"
    print("OK: _classify_chip handles copy variations + drops unknown chips.")

    # --- Bonus: listing-URL filter ---
    from cars.spiders.cars_spider import LISTING_URL_RE
    listing_url_cases = [
        # Real listing URLs (must match)
        ("https://eg.hatla2ee.com/en/car/kia/sportage/7210056",      True),
        ("https://eg.hatla2ee.com/en/car/volks-wagen/cc/7210036",    True),
        ("https://eg.hatla2ee.com/en/car/renault/logan/7210017",     True),
        ("https://eg.hatla2ee.com/en/car/kia/ceed/7210037/",         True),
        ("https://eg.hatla2ee.com/en/car/kia/ceed/7210037?ref=foo",  True),
        # Non-listing URLs (must NOT match)
        ("https://eg.hatla2ee.com/en/car/volks-wagen/cc",            False),  # model index
        ("https://eg.hatla2ee.com/en/car/volks-wagen",               False),  # brand index
        ("https://eg.hatla2ee.com/en/car/renault/logan",             False),  # model index
        ("https://eg.hatla2ee.com/en/car/kia/ceed",                  False),  # model index
        ("https://eg.hatla2ee.com/en/car/city/6-october",            False),  # location index
        ("https://eg.hatla2ee.com/en/car/kia/ceed/teraz/990",        False),  # promo sub-cat
        ("https://eg.hatla2ee.com/en/car",                           False),  # root
    ]
    for url, want in listing_url_cases:
        got = bool(LISTING_URL_RE.search(url))
        assert got == want, f"LISTING_URL_RE.search({url!r}) -> {got}, expected {want}"
    print("OK: LISTING_URL_RE accepts real detail URLs and rejects index/promo URLs.")

    # --- Bonus: parse_car_page drops items with no Brand AND no Price ---
    bare_html = "<html><body><h1>Not a real listing</h1></body></html>"
    bare_url = "https://eg.hatla2ee.com/en/car/some/index"
    bare_resp = HtmlResponse(
        url=bare_url, body=bare_html.encode("utf-8"),
        encoding="utf-8", request=Request(bare_url),
    )
    spider2 = CarsSpider()
    bare_items = list(spider2.parse_car_page(bare_resp))
    assert bare_items == [], f"expected no items from bare page, got {bare_items}"
    print("OK: parse_car_page drops items with no Brand and no Price.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
