# Egypt Cars Market — Hatla2ee → PostgreSQL → Bruin → Power BI

End-to-end data pipeline for car listings scraped from
[hatla2ee.com](https://eg.hatla2ee.com/en/car):

```
Scrapy spider  →  raw.cars (PostgreSQL)  →  Bruin transforms  →  Star schema  →  Power BI
```

![](img.png)

## Stack

| Layer             | Tool                                    |
| ----------------- | --------------------------------------- |
| Ingestion         | Scrapy (Python)                         |
| Warehouse         | PostgreSQL 16                           |
| DB UI             | pgAdmin 4                               |
| Transformations   | [Bruin](https://getbruin.com) (`pg.sql`) |
| BI / Dashboard    | Power BI Desktop (Import mode)          |
| Orchestration     | Docker Compose                          |

Everything except Power BI runs in Docker — no need to install Python,
Postgres, or the Bruin CLI on your host.

## Quickstart

Prerequisites: [Docker](https://docs.docker.com/get-docker/) and
`make` (optional but convenient).

```bash
# 1. Configure credentials
cp .env.example .env            # edit values if you want

# 2. Bring up Postgres + pgAdmin
make up

# 3. Scrape listings into raw.cars
make scrape

# 4. (Optional) Seed raw.cars with synthetic data if the live site is blocked
make seed-raw

# 5. Run Bruin transforms to build the star schema
make bruin-validate    # static-check the assets
make transform         # build staging.cars + dim_* + fact_car_listings
```

Then connect Power BI Desktop to `localhost:5432` using the credentials
in `.env` and import the tables from the `marts` schema.

### Useful `make` targets

```
make help            # list all targets
make up              # start postgres + pgadmin
make down            # stop the stack (volumes preserved)
make logs            # tail logs from all services
make ps              # show running containers
make psql            # open a psql shell inside the postgres container
make scrape          # run the cars spider in the scrapy container
make shell-scrapy    # interactive shell in the scrapy container
make transform       # run the bruin pipeline (raw → staging → dims → fact)
make bruin-validate  # static-check bruin_pipeline/ config + asset SQL
make seed-raw        # insert ~10 synthetic rows into raw.cars (no live site needed)
make smoke-pipeline  # smoke-test the Scrapy item pipeline end-to-end
make clean           # stop AND delete volumes (DESTROYS data)
```

### Services

| Service    | URL / Port                    | Credentials                     |
| ---------- | ----------------------------- | ------------------------------- |
| PostgreSQL | `localhost:5432`              | `POSTGRES_USER` / `POSTGRES_PASSWORD` from `.env` |
| pgAdmin    | <http://localhost:5050>       | `PGADMIN_DEFAULT_EMAIL` / `PGADMIN_DEFAULT_PASSWORD` |

On first connect in pgAdmin, register a new server with:

- Host: `postgres` (the service name inside the Docker network)
- Port: `5432`
- Username / Password / Database: values from `.env`

## Repository layout

```
.
├── docker-compose.yml          # postgres + pgadmin + scrapy + bruin
├── .env.example                # copy to .env
├── Makefile                    # task shortcuts
├── requirements.txt            # Python deps for the scrapy container
├── docker/
│   └── scrapy/Dockerfile       # scrapy runner image
├── sql/init/                   # runs on first postgres boot
│   └── 01_schemas.sql          # creates raw / staging / marts schemas
├── cars/                       # existing Scrapy project
│   ├── items.py
│   ├── pipelines.py
│   ├── settings.py
│   └── spiders/cars_spider.py
├── scrapy.cfg
├── .bruin.yml                  # Bruin connections (lives at the repo root)
├── bruin_pipeline/
│   ├── pipeline.yml
│   └── assets/
│       ├── staging/staging.cars.sql
│       ├── dimensions/dim_*.sql
│       └── facts/fact_car_listings.sql
└── Cars dashboard.pdf          # Power BI dashboard export
```

## Ingestion

The spider writes scraped items to `raw.cars` via
[`cars/pipelines.py`](./cars/pipelines.py):

- `CleanItemPipeline` trims whitespace from string fields.
- `PostgresPipeline` upserts each item into `raw.cars`, keyed by `link`. Items
  are batched (50 per flush) for fewer round-trips. Re-running the spider
  updates existing rows in place and bumps `updated_at`.

The table schema is in [`sql/init/02_raw_cars.sql`](./sql/init/02_raw_cars.sql)
and is created automatically on first boot of the postgres container.

A quick smoke-test (no live site needed) is available:

```bash
docker compose run --rm --entrypoint python scrapy scripts/smoke_test_pipeline.py
```

## Transformations (Bruin)

The Bruin pipeline takes the flat `raw.cars` text dump and turns it into a
star schema in the `marts` schema, with a `staging.cars` cleaned view in
between:

```
raw.cars  ──►  staging.cars  ──►  marts.dim_*  ──►  marts.fact_car_listings
```

- **`staging.cars`** ([`bruin_pipeline/assets/staging/staging.cars.sql`](./bruin_pipeline/assets/staging/staging.cars.sql))
  casts `price` and `km` to `INTEGER` (NULL on garbage), parses a 4-digit
  `model_year` out of the free-text `used_since`, and trims +
  title-cases all string columns.
- **Dimensions** ([`bruin_pipeline/assets/dimensions/`](./bruin_pipeline/assets/dimensions/)):
  `dim_make`, `dim_model` (carries `make_id`), `dim_fuel`,
  `dim_transmission`, `dim_body_style`, `dim_color`, `dim_city`,
  `dim_year`. Surrogate keys are generated deterministically with
  `DENSE_RANK`. Each dim has a sentinel row (`id=0`, name `'Unknown'`)
  so the fact table's FK columns can be `NOT NULL` even when the source
  value is missing.
- **`fact_car_listings`** ([`bruin_pipeline/assets/facts/fact_car_listings.sql`](./bruin_pipeline/assets/facts/fact_car_listings.sql))
  joins all dimensions and exposes the measures (`price_egp`, `km`).

Quality checks (`not_null`, `unique`, `non_negative`) are declared in the
asset YAML headers and Bruin runs them automatically after each asset
— see the `make transform` output for results.

## Roadmap

- [x] Docker backbone: Postgres + pgAdmin + containerised Scrapy & Bruin
- [x] PostgreSQL item pipeline (writes to `raw.cars`, upsert by link)
- [x] Bruin assets: `staging.cars` + dimension tables + `fact_car_listings`
- [x] Data-quality checks on every layer
- [ ] Refresh the Power BI dashboard against the star schema
