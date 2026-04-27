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

# 4. (Next PR) Run Bruin transforms to build the star schema
make transform
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
make transform       # run the bruin pipeline
make bruin-validate  # validate bruin_pipeline/ config
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
├── bruin_pipeline/
│   ├── .bruin.yml              # Postgres connection
│   ├── pipeline.yml
│   └── assets/                 # SQL assets (added in a follow-up PR)
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

## Roadmap

- [x] Docker backbone: Postgres + pgAdmin + containerised Scrapy & Bruin
- [x] PostgreSQL item pipeline (writes to `raw.cars`, upsert by link)
- [ ] Bruin assets: `staging.cars` + dimension tables + `fact_car_listings`
- [ ] Data-quality checks on the staging layer
- [ ] Refresh the Power BI dashboard against the star schema
