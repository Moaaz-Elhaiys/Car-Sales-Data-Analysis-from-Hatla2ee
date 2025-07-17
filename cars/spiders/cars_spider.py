import scrapy
from cars.items import CarItem
from urllib.parse import urlencode
import random

user_agent_list = [
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/93.0.4577.82 Safari/537.36',
    'Mozilla/5.0 (iPhone; CPU iPhone OS 14_4_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0.3 Mobile/15E148 Safari/604.1',
    'Mozilla/4.0 (compatible; MSIE 9.0; Windows NT 6.1)',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/87.0.4280.141 Safari/537.36 Edg/87.0.664.75',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/70.0.3538.102 Safari/537.36 Edge/18.18363',
]

headers = {"User-Agent": random.choice(user_agent_list)}

class CarsSpider(scrapy.Spider):
    name = "cars"
    allowed_domains = ["eg.hatla2ee.com"]
    start_urls = ["https://eg.hatla2ee.com/en/car"]
    seen_urls = set()

    custom_settings = {
        "FEEDS" :  {
        "cars.csv" : {"format" : "csv", "append" : True } 
            }
    }


    def parse(self, response):
        base_url = "https://eg.hatla2ee.com"

        car_links = response.xpath("//div[@class='newCarListUnit_header']/span/a/@href").getall()

        for car_link in car_links:
            car_url = base_url + car_link
            yield response.follow(url=car_url, callback=self.parse_car_page, headers=headers)

        next_page = response.xpath("//div[@class='pagination pagination-right']//li[@class='active']/following-sibling::li[1]/a/@href").get()
        if "page" in next_page:
            next_page_url = base_url + next_page
            yield response.follow(url=next_page_url, callback=self.parse, headers=headers)
            
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