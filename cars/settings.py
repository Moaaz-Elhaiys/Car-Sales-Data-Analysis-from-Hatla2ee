# Scrapy settings for cars project


SPIDER_MODULES = ["cars.spiders"]
NEWSPIDER_MODULE = "cars.spiders"


# Crawl responsibly by identifying yourself (and your website) on the user-agent
#USER_AGENT = "cars (+http://www.yourdomain.com)"
# 1. Be polite but hide the 'Scrapy' identity
USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'
DEFAULT_REQUEST_HEADERS = {
   'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
   'Accept-Language': 'en-US,en;q=0.9',
   'Accept-Encoding': 'gzip, deflate, br',
   'Connection': 'keep-alive',
}
# 2. Disable robots.txt (Hatla2ee often uses this to block bots)
ROBOTSTXT_OBEY = False

# 3. Add a delay to look more human
DOWNLOAD_DELAY = 3
RANDOMIZE_DOWNLOAD_DELAY = True

# 4. Enable cookies
COOKIES_ENABLED = True

CONCURRENT_REQUESTS = 1



# Configure item pipelines
# See https://docs.scrapy.org/en/latest/topics/item-pipeline.html
ITEM_PIPELINES = {
    "cars.pipelines.CleanItemPipeline": 300,
    "cars.pipelines.PostgresPipeline": 400,
}

# Postgres connection (env vars override these defaults; see docker-compose.yml).
POSTGRES_HOST = "postgres"
POSTGRES_PORT = 5432
POSTGRES_DB = "cars"
POSTGRES_USER = "cars"
POSTGRES_PASSWORD = "cars"
POSTGRES_BATCH_SIZE = 50


# Set settings whose default value is deprecated to a future-proof value
REQUEST_FINGERPRINTER_IMPLEMENTATION = "2.7"
TWISTED_REACTOR = "twisted.internet.asyncioreactor.AsyncioSelectorReactor"
FEED_EXPORT_ENCODING = "utf-8"
# Enable scrapy-impersonate download handlers
DOWNLOAD_HANDLERS = {
    "http": "scrapy_impersonate.ImpersonateDownloadHandler",
    "https": "scrapy_impersonate.ImpersonateDownloadHandler",
}