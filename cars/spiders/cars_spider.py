import scrapy
from cars.items import CarItem
from urllib.parse import urlencode


class CarsSpider(scrapy.Spider):
    name = "cars"
    allowed_domains = ["eg.hatla2ee.com"]
    seen_urls = set()

    # DELETE the start_urls line and add this method instead:
    def start_requests(self):
        url = "https://eg.hatla2ee.com/en/car"
        # This meta tag is what actually turns on the anti-bot bypass!
        yield scrapy.Request(url, callback=self.parse, meta={"impersonate": "chrome110"})

    def parse(self, response):
        base_url = "https://eg.hatla2ee.com"

        car_links = response.xpath("//div[@data-slot='card-content']//a/@href").getall()

        for car_link in car_links:
            car_url = base_url + car_link
            yield response.follow(url=car_url, callback=self.parse_car_page, meta={"impersonate": "chrome110"})

        next_page = response.xpath("//div[@class='pagination pagination-right']//li[@class='active']/following-sibling::li[1]/a/@href").get()
        if next_page and "page" in next_page:
            next_page_url = base_url + next_page
            yield response.follow(url=next_page_url, callback=self.parse, meta={"impersonate": "chrome110"})
            
    def parse_car_page(self, response):
        car_item = CarItem()

        car_item['Link'] = response.url
        if car_item['Link'] in self.seen_urls:
            return  # Skip duplicate
        self.seen_urls.add(car_item['Link'])

        # Extract title and price
        car_item['Title'] = response.xpath("//div[@class='usedCarTitleWrap']/h1/text()").get(default='').strip()

        price_raw = response.xpath("//div[@class='usedUnitPriceNumb']//span[@class='usedUnitCarPrice']/text()").get()
        if price_raw:
            car_item['Price'] = price_raw.strip().split(" ")[0].replace(",", "")
        else:
            car_item['Price'] = ''


        # Map scraped feature titles to CarItem fields
        field_map = {
            "Make": "Make",
            "Model": "Model",
            "Fuel": "Fuel",
            "Transmission": "Transmission",
            "Color": "Color",
            "Class": "Class",
            "Km": "Km",
            "Used since": "Used_since",
            "Body Style": "Body_style",
            "City": "City"
        }

        # Select all features and values correctly
        features = response.xpath("//div[@class='DescDataItem']//span[@class='DescDataSubTit']/text()").getall()
        values = response.xpath("//div[@class='DescDataItem']//span[@class='DescDataVal']/text()").getall()

        for i, feature in enumerate(features):
            feature = feature.strip()
            if feature in field_map and i < len(values):
                value = values[i].strip()
                mapped_field = field_map[feature]
                car_item[mapped_field] = value

        yield car_item