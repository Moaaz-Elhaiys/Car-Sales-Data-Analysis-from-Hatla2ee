import re

import scrapy

from cars.items import CarItem


# Match the trailing numeric id in a listing URL, e.g. ".../car/12345" or
# ".../car/12345/". The id is the segment between the last slash and the
# end of the path (or before a query string).
EXTERNAL_ID_RE = re.compile(r"/(\d+)/?(?:[?#].*)?$")

DIGITS_RE = re.compile(r"\d[\d,]*")
YEAR_RE = re.compile(r"^\d{4}$")
KM_RE = re.compile(r"\d.*KM", re.IGNORECASE)

# Substring tokens (case-insensitive) that mark a top-chip as a transmission /
# fuel value. Substring-matching makes us resilient to copy variations such as
# "Automatic Transmission" or "Diesel Engine".
TRANSMISSION_TOKENS = ("automatic", "manual", "cvt", "tiptronic", "semi-auto")
FUEL_TOKENS = (
    "gas", "gasoline", "petrol", "diesel", "hybrid", "electric",
    "ev", "lpg", "cng", "natural gas",
)


def _digits_only(text: str | None) -> str | None:  # sourcery skip: assign-if-exp, swap-if-else-branches, use-named-expression
    """Return the first numeric run in ``text`` with commas/spaces stripped."""
    if not text:
        return None
    m = DIGITS_RE.search(text)
    if not m:
        return None
    return m.group(0).replace(",", "").replace(" ", "")


def _classify_chip(value: str) -> str | None:
    # sourcery skip: assign-if-exp, reintroduce-else
    """Return one of {"year", "km", "transmission", "fuel"} for a top-chip value.

    The four chips on a hatla2ee detail page have no textual labels (only icons),
    so we infer the slot from the value's shape. We only return a slot we
    recognize; unknown chips are dropped (returning ``None``) so a future fifth
    chip won't accidentally clobber `Fuel`.
    """
    v = value.strip()
    if not v:
        return None
    if YEAR_RE.match(v):
        return "year"
    if KM_RE.search(v):
        return "km"
    lo = v.lower()
    if any(tok in lo for tok in TRANSMISSION_TOKENS):
        return "transmission"
    if any(tok in lo for tok in FUEL_TOKENS):
        return "fuel"
    return None


class CarsSpider(scrapy.Spider):
    name = "cars"
    allowed_domains = ["eg.hatla2ee.com"]
    seen_urls: set[str] = set()

    def start_requests(self):
        url = "https://eg.hatla2ee.com/en/car"
        yield scrapy.Request(
            url,
            callback=self.parse,
            meta={"impersonate": "chrome110"},
        )

    def parse(self, response):
        base_url = "https://eg.hatla2ee.com"

        car_links = response.xpath(
            "//div[@data-slot='card-content']//a/@href"
        ).getall()

        for car_link in car_links:
            if not EXTERNAL_ID_RE.search(car_link):
                continue
            car_url = car_link if car_link.startswith("http") else base_url + car_link
            yield response.follow(
                url=car_url,
                callback=self.parse_car_page,
                meta={"impersonate": "chrome110"},
            )

        next_page = response.xpath(
                    "//ul[@data-slot='pagination-content']"
                    "//li[a[@data-active='true']]/following-sibling::li/a/@href"
                ).get()

        if next_page and "page" in next_page:
            next_page_url = base_url + next_page
            yield response.follow(
                url=next_page_url,
                callback=self.parse,
                meta={"impersonate": "chrome110"},
            )

    def parse_car_page(self, response):
        if response.url in self.seen_urls:
            return
        self.seen_urls.add(response.url)

        item = CarItem()

        # Identity
        item["Link"] = response.url
        m = EXTERNAL_ID_RE.search(response.url)
        item["ExternalId"] = m.group(1) if m else None

        # Price -- first bold span inside #listing-overview, digits only.
        price_text = response.xpath(
            "//div[@id='listing-overview']"
            "//span[contains(@class,'font-bold')][1]/text()"
        ).get()
        item["Price"] = _digits_only(price_text)

        # Top chips (year / km / transmission / fuel). Each chip is a flex pill
        # with bg-gray-50 + rounded-md *and* a shrink-0 icon sibling -- the
        # icon sibling is what disambiguates these from any other pill that
        # happens to reuse the bg-gray-50 styling elsewhere on the page.
        chip_values = response.xpath(
            "//div[contains(@class,'bg-gray-50')"
            "      and contains(@class,'rounded-md')"
            "      and .//div[contains(@class,'shrink-0')]]"
            "//div[contains(@class,'flex-col')]/span/text()"
        ).getall()

        for raw in chip_values:
            slot = _classify_chip(raw)
            if slot == "year":
                item["ReleaseYear"] = raw.strip()
            elif slot == "km":
                item["Km"] = _digits_only(raw)
            elif slot == "transmission":
                item["Transmission"] = raw.strip()
            elif slot == "fuel":
                item["Fuel"] = raw.strip()

        # "Car Details" panel: each row is a label div (text-muted-foreground)
        # followed by a value div as its next sibling. We look up by label.
        def detail(label: str) -> str | None:
            value = response.xpath(
                "//div[contains(@class,'text-muted-foreground')"
                f" and normalize-space(.)='{label}']"
                "/following-sibling::div[1]//text()"
            ).get()
            return value.strip() if value else None

        item["Brand"] = detail("Brand")
        item["Model"] = detail("Model")
        item["Condition"] = detail("Condition")
        item["Color"] = detail("Color")
        item["CC"] = _digits_only(detail("CC"))
        item["Location"] = detail("Location")
        item["OriginCountry"] = detail("Origin Country")
        item["AssemblyCountry"] = detail("Assembly Country")

        yield item
