# Define here the models for your scraped items
# See: https://docs.scrapy.org/en/latest/topics/items.html

import scrapy


class CarItem(scrapy.Item):
    # Identity
    ExternalId = scrapy.Field()
    Link = scrapy.Field()

    # Top-of-page chips
    ReleaseYear = scrapy.Field()
    Km = scrapy.Field()
    Transmission = scrapy.Field()
    Fuel = scrapy.Field()

    # Price
    Price = scrapy.Field()

    # "Car Details" panel
    Brand = scrapy.Field()
    Model = scrapy.Field()
    Condition = scrapy.Field()
    Color = scrapy.Field()
    CC = scrapy.Field()
    Location = scrapy.Field()
    OriginCountry = scrapy.Field()
    AssemblyCountry = scrapy.Field()
