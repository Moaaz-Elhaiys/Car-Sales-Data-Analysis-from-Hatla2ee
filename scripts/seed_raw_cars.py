"""Insert a small synthetic dataset into raw.cars for end-to-end pipeline tests.

Run inside the scrapy container:
    docker compose run --rm --entrypoint python scrapy scripts/seed_raw_cars.py
"""

from __future__ import annotations

import os
import sys

import psycopg2
from psycopg2.extras import execute_values

ROWS = [
    # link, title, price, make, model, fuel, transmission, color, class, km, used_since, body_style, city
    ("https://example.com/seed/1",  "Toyota Corolla 2020",  "350000",  "Toyota",  "Corolla", "Petrol", "Automatic", "White",  "Sedan",      "120000", "2020", "Sedan",     "Cairo"),
    ("https://example.com/seed/2",  "Toyota Corolla 2019",  "320000",  "Toyota",  "Corolla", "Petrol", "Manual",    "Silver", "Sedan",      "150000", "2019", "Sedan",     "Cairo"),
    ("https://example.com/seed/3",  "Honda Civic 2021",     "420000",  "Honda",   "Civic",   "Petrol", "Automatic", "Black",  "Sedan",      "80000",  "2021", "Sedan",     "Giza"),
    ("https://example.com/seed/4",  "Hyundai Elantra 2022", "500000",  "Hyundai", "Elantra", "Petrol", "Automatic", "Red",    "Sedan",      "40000",  "2022", "Sedan",     "Alexandria"),
    ("https://example.com/seed/5",  "Kia Sportage 2020",    "650000",  "Kia",     "Sportage","Diesel", "Automatic", "Grey",   "SUV",        "70000",  "2020", "SUV",       "Cairo"),
    ("https://example.com/seed/6",  "Nissan Sunny 2018",    "230000",  "Nissan",  "Sunny",   "Petrol", "Manual",    "Blue",   "Sedan",      "180000", "2018", "Sedan",     "Cairo"),
    ("https://example.com/seed/7",  "BMW 320i 2017",        "750000",  "BMW",     "320i",    "Petrol", "Automatic", "Black",  "Sedan",      "100000", "2017", "Sedan",     "Giza"),
    ("https://example.com/seed/8",  "Mercedes C200 2019",  "1100000",  "Mercedes","C200",    "Petrol", "Automatic", "White",  "Sedan",      "60000",  "2019", "Sedan",     "Alexandria"),
    # Edge cases:
    ("https://example.com/seed/9",  "Used Chevy Optra",     "EGP 95,000", "chevy", "optra",  "petrol", "manual",    "white",  "Sedan",      "220 000","Used since 2010", "sedan", "  cairo "),
    ("https://example.com/seed/10", "Mystery car",          "",          None,    None,      None,     None,        None,     None,         None,     None,    None,        None),
]

INSERT_SQL = """
INSERT INTO raw.cars (
    link, title, price, make, model, fuel, transmission,
    color, class, km, used_since, body_style, city
) VALUES %s
ON CONFLICT (link) DO UPDATE SET
    title=EXCLUDED.title, price=EXCLUDED.price, make=EXCLUDED.make,
    model=EXCLUDED.model, fuel=EXCLUDED.fuel, transmission=EXCLUDED.transmission,
    color=EXCLUDED.color, class=EXCLUDED.class, km=EXCLUDED.km,
    used_since=EXCLUDED.used_since, body_style=EXCLUDED.body_style, city=EXCLUDED.city,
    updated_at=NOW();
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
