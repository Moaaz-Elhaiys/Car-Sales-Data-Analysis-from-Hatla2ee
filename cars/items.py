# Define here the models for your scraped items
#
# See documentation in:
# https://docs.scrapy.org/en/latest/topics/items.html

import scrapy

class CarItem(scrapy.Item):
    Title = scrapy.Field()
    Price = scrapy.Field()
    Make = scrapy.Field()
    Model = scrapy.Field()
    Fuel = scrapy.Field()
    Transmission = scrapy.Field()
    Color = scrapy.Field()
    Class = scrapy.Field()
    Km = scrapy.Field()
    Used_since = scrapy.Field()
    Body_style = scrapy.Field()
    City = scrapy.Field()
    Link = scrapy.Field() 