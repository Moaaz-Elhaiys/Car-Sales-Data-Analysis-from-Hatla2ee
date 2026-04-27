# Scrapy item pipelines.
# See: https://docs.scrapy.org/en/latest/topics/item-pipeline.html

import logging
import os

import psycopg2
from itemadapter import ItemAdapter
from psycopg2.extras import execute_batch

logger = logging.getLogger(__name__)


class CleanItemPipeline:
    """Trim whitespace from string fields (kept from the original project)."""

    SKIP_FIELDS = {"Title", "Price", "Link"}

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
            link, title, price, make, model, fuel, transmission,
            color, class, km, used_since, body_style, city
        ) VALUES (
            %(link)s, %(title)s, %(price)s, %(make)s, %(model)s, %(fuel)s, %(transmission)s,
            %(color)s, %(class)s, %(km)s, %(used_since)s, %(body_style)s, %(city)s
        )
        ON CONFLICT (link) DO UPDATE SET
            title        = EXCLUDED.title,
            price        = EXCLUDED.price,
            make         = EXCLUDED.make,
            model        = EXCLUDED.model,
            fuel         = EXCLUDED.fuel,
            transmission = EXCLUDED.transmission,
            color        = EXCLUDED.color,
            class        = EXCLUDED.class,
            km           = EXCLUDED.km,
            used_since   = EXCLUDED.used_since,
            body_style   = EXCLUDED.body_style,
            city         = EXCLUDED.city,
            updated_at   = NOW();
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
            "link":         link,
            "title":        adapter.get("Title"),
            "price":        adapter.get("Price"),
            "make":         adapter.get("Make"),
            "model":        adapter.get("Model"),
            "fuel":         adapter.get("Fuel"),
            "transmission": adapter.get("Transmission"),
            "color":        adapter.get("Color"),
            "class":        adapter.get("Class"),
            "km":           adapter.get("Km"),
            "used_since":   adapter.get("Used_since"),
            "body_style":   adapter.get("Body_style"),
            "city":         adapter.get("City"),
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
            logger.info("PostgresPipeline upserted %d rows into raw.cars", len(self._buffer))
            self._buffer.clear()
