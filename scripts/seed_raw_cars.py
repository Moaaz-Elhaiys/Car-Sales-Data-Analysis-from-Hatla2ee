"""Insert a small synthetic dataset into raw.cars for end-to-end pipeline tests.

Run inside the scrapy container:
    docker compose run --rm --entrypoint python scrapy scripts/seed_raw_cars.py
"""

from __future__ import annotations

import os
import sys

import psycopg2
from psycopg2.extras import execute_values

# Columns: external_id, link, brand, model, price, condition, color, cc,
#          location, origin_country, assembly_country,
#          release_year, km, transmission, fuel
ROWS = [
    ("1001", "https://example.com/seed/1001", "Toyota",   "Corolla",  "350000",  "Used", "White",  "1600", "Cairo",      "Japan",   "Egypt",   "2020", "120000", "Automatic", "Petrol"),
    ("1002", "https://example.com/seed/1002", "Toyota",   "Corolla",  "320000",  "Used", "Silver", "1600", "Cairo",      "Japan",   "Egypt",   "2019", "150000", "Manual",    "Petrol"),
    ("1003", "https://example.com/seed/1003", "Honda",    "Civic",    "420000",  "Used", "Black",  "1800", "Giza",       "Japan",   "Japan",   "2021", "80000",  "Automatic", "Petrol"),
    ("1004", "https://example.com/seed/1004", "Hyundai",  "Elantra",  "500000",  "Used", "Red",    "1600", "Alexandria", "Korea",   "Egypt",   "2022", "40000",  "Automatic", "Petrol"),
    ("1005", "https://example.com/seed/1005", "Kia",      "Sportage", "650000",  "Used", "Grey",   "2000", "Cairo",      "Korea",   "Korea",   "2020", "70000",  "Automatic", "Diesel"),
    ("1006", "https://example.com/seed/1006", "Nissan",   "Sunny",    "230000",  "Used", "Blue",   "1500", "Cairo",      "Japan",   "Egypt",   "2018", "180000", "Manual",    "Petrol"),
    ("1007", "https://example.com/seed/1007", "BMW",      "320i",     "750000",  "Used", "Black",  "2000", "Giza",       "Germany", "Germany", "2017", "100000", "Automatic", "Petrol"),
    ("1008", "https://example.com/seed/1008", "Mercedes", "C200",    "1100000",  "Used", "White",  "2000", "Alexandria", "Germany", "Germany", "2019", "60000",  "Automatic", "Petrol"),
    # Edge cases:
    # 1009 -- raw-ish values straight from a noisy scrape (mixed case, spaces).
    ("1009", "https://example.com/seed/1009", "chevy",    "optra",   "EGP 95,000", "used", "white",  " 1600", "  cairo  ", "korea",   "egypt",   "2010", "220 000", "manual",    "petrol"),
    # 1010 -- mostly-NULL row to exercise sentinel handling in the dim layer.
    ("1010", "https://example.com/seed/1010", None,       None,       "",          None,   None,     None,    None,        None,      None,      None,   None,      None,        None),
    # 1011 -- listing whose values literally normalise to "Unknown" must not
    # collide with the sentinel rows added later in the dim tables.
    ("1011", "https://example.com/seed/1011", "unknown",  "unknown",  "180000",   "Used", "Unknown", "1600", "Unknown",    "Unknown", "Unknown", "2015", "100000", "Manual",    "Petrol"),
]

INSERT_SQL = """
INSERT INTO raw.cars (
    external_id, link, brand, model, price, condition, color, cc,
    location, origin_country, assembly_country,
    release_year, km, transmission, fuel
) VALUES %s
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


def main() -> int:
    conn = psycopg2.connect(
        host=os.getenv("POSTGRES_HOST", "postgres"),
        port=int(os.getenv("POSTGRES_PORT", 5432)),
        dbname=os.getenv("POSTGRES_DB", "cars"),
        user=os.getenv("POSTGRES_USER", "cars"),
        password=os.getenv("POSTGRES_PASSWORD", "cars"),
    )
    try:
        with conn, conn.cursor() as cur:
            execute_values(cur, INSERT_SQL, ROWS)
            cur.execute("SELECT COUNT(*) FROM raw.cars")
            (count,) = cur.fetchone()
        print(f"Seeded raw.cars; total rows now: {count}")
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
