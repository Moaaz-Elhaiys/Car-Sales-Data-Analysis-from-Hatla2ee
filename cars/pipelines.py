# Scrapy item pipelines.
# See: https://docs.scrapy.org/en/latest/topics/item-pipeline.html

import logging
import os

import psycopg2
from itemadapter import ItemAdapter
from psycopg2.extras import execute_batch

logger = logging.getLogger(__name__)


class CleanItemPipeline:
    """Trim whitespace from string fields.

    Numeric/identity fields are skipped because the spider already normalises
    them (digits-only) -- trimming there would be redundant.
    """

    SKIP_FIELDS = {"Link", "ExternalId", "Price", "Km", "CC"}

    def process_item(self, item, spider):
        adapter = ItemAdapter(item)
        for field_name in adapter.field_names():
            if field_name in self.SKIP_FIELDS:
                continue
            value = adapter.get(field_name)
            if isinstance(value, str):
                adapter[field_name] = value.strip()
        return item


class PostgresPipeline:
    """Upsert each scraped item into raw.cars, keyed by link."""

    UPSERT_SQL = """
        INSERT INTO raw.cars (
            external_id, link, brand, model, price, condition, color, cc,
            location, origin_country, assembly_country,
            release_year, km, transmission, fuel
        ) VALUES (
            %(external_id)s, %(link)s, %(brand)s, %(model)s, %(price)s,
            %(condition)s, %(color)s, %(cc)s, %(location)s,
            %(origin_country)s, %(assembly_country)s,
            %(release_year)s, %(km)s, %(transmission)s, %(fuel)s
        )
        ON CONFLICT (link) DO UPDATE SET
            external_id      = EXCLUDED.external_id,
            brand            = EXCLUDED.brand,
            model            = EXCLUDED.model,
            price            = EXCLUDED.price,
            condition        = EXCLUDED.condition,
            color            = EXCLUDED.color,
            cc               = EXCLUDED.cc,
            location         = EXCLUDED.location,
            origin_country   = EXCLUDED.origin_country,
            assembly_country = EXCLUDED.assembly_country,
            release_year     = EXCLUDED.release_year,
            km               = EXCLUDED.km,
            transmission     = EXCLUDED.transmission,
            fuel             = EXCLUDED.fuel,
            updated_at       = NOW();
    """

    def __init__(self, host, port, dbname, user, password, batch_size):
        self.host = host
        self.port = port
        self.dbname = dbname
        self.user = user
        self.password = password
        self.batch_size = batch_size
        self.conn = None
        self.cur = None
        self._buffer = []

    @classmethod
    def from_crawler(cls, crawler):
        s = crawler.settings
        return cls(
            host=os.getenv("POSTGRES_HOST", s.get("POSTGRES_HOST", "postgres")),
            port=int(os.getenv("POSTGRES_PORT", s.get("POSTGRES_PORT", 5432))),
            dbname=os.getenv("POSTGRES_DB", s.get("POSTGRES_DB", "cars")),
            user=os.getenv("POSTGRES_USER", s.get("POSTGRES_USER", "cars")),
            password=os.getenv("POSTGRES_PASSWORD", s.get("POSTGRES_PASSWORD", "cars")),
            batch_size=int(s.get("POSTGRES_BATCH_SIZE", 50)),
        )

    def open_spider(self, spider):
        logger.info(
            "PostgresPipeline connecting to %s:%s/%s as %s",
            self.host, self.port, self.dbname, self.user,
        )
        self.conn = psycopg2.connect(
            host=self.host,
            port=self.port,
            dbname=self.dbname,
            user=self.user,
            password=self.password,
        )
        self.conn.autocommit = False
        self.cur = self.conn.cursor()

    def close_spider(self, spider):
        try:
            self._flush()
        finally:
            if self.cur is not None:
                self.cur.close()
            if self.conn is not None:
                self.conn.close()

    def process_item(self, item, spider):
        adapter = ItemAdapter(item)
        link = adapter.get("Link")
        if not link:
            logger.warning("Skipping item without Link: %r", dict(adapter))
            return item

        row = {
            "external_id":      adapter.get("ExternalId"),
            "link":             link,
            "brand":            adapter.get("Brand"),
            "model":            adapter.get("Model"),
            "price":            adapter.get("Price"),
            "condition":        adapter.get("Condition"),
            "color":            adapter.get("Color"),
            "cc":               adapter.get("CC"),
            "location":         adapter.get("Location"),
            "origin_country":   adapter.get("OriginCountry"),
            "assembly_country": adapter.get("AssemblyCountry"),
            "release_year":     adapter.get("ReleaseYear"),
            "km":               adapter.get("Km"),
            "transmission":     adapter.get("Transmission"),
            "fuel":             adapter.get("Fuel"),
        }
        self._buffer.append(row)

        if len(self._buffer) >= self.batch_size:
            self._flush()

        return item

    def _flush(self):
        if not self._buffer or self.cur is None or self.conn is None:
            return
        try:
            execute_batch(self.cur, self.UPSERT_SQL, self._buffer, page_size=self.batch_size)
            self.conn.commit()
        except Exception:
            self.conn.rollback()
            logger.exception(
                "PostgresPipeline failed to flush %d rows; rolling back (buffer kept for retry)",
                len(self._buffer),
            )
            raise
        else:
            self._buffer.clear()
