SHELL := /bin/bash

# Ensure .env exists so docker compose --env-file substitutions don't blow up.
ifeq (,$(wildcard .env))
$(warning .env not found -- copy .env.example to .env before running targets that need it)
endif

.PHONY: help up down restart logs ps psql scrape shell-scrapy transform full-refresh bruin-validate seed-raw smoke-pipeline migrate build clean import-historical

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

up: ## Start postgres + pgadmin in the background
	docker compose up -d postgres pgadmin

down: ## Stop and remove all containers (keeps volumes)
	docker compose down

restart: down up ## Restart the stack

logs: ## Tail logs from all running services
	docker compose logs -f

ps: ## List running services
	docker compose ps

psql: ## Open a psql shell against the running postgres container
	docker compose exec postgres psql -U $${POSTGRES_USER:-cars} -d $${POSTGRES_DB:-cars}

build: ## (Re)build local images (scrapy)
	docker compose build scrapy

scrape: ## Run the cars spider inside the scrapy container
	docker compose run --rm scrapy scrapy crawl cars

shell-scrapy: ## Open an interactive shell inside the scrapy container
	docker compose run --rm --entrypoint bash scrapy

# How many days back the incremental load should sweep on each `make transform`.
# 7d default covers yesterday + a buffer for late-arriving spider mutations.
# Override with `make transform INCREMENTAL_DAYS=1` for tighter windows.
INCREMENTAL_DAYS ?= 7

# `date` flag flavour differs across platforms: GNU (Linux, WSL) uses `-d`,
# BSD (macOS) uses `-v`. Detect once and stamp the right command into the
# recipe so `make transform` works on either host without an extra container.
ifeq ($(shell uname -s),Darwin)
  DATE_DAYS_AGO = $$(date -u -v-$(INCREMENTAL_DAYS)d +%Y-%m-%d)
  DATE_TOMORROW = $$(date -u -v+1d                  +%Y-%m-%d)
else
  DATE_DAYS_AGO = $$(date -u -d '$(INCREMENTAL_DAYS) days ago' +%Y-%m-%d)
  DATE_TOMORROW = $$(date -u -d 'tomorrow'                     +%Y-%m-%d)
endif

transform: ## Incremental run — only re-process raw.cars rows updated in the last $INCREMENTAL_DAYS (default 7)
	docker compose run --rm bruin run \
	    --start-date $(DATE_DAYS_AGO) \
	    --end-date   $(DATE_TOMORROW) \
	    /workspace/bruin_pipeline

full-refresh: ## Rebuild the warehouse from scratch (drops + reloads every staging row)
	docker compose run --rm bruin run --full-refresh \
	    --start-date 1970-01-01 --end-date 2999-12-31 \
	    /workspace/bruin_pipeline

bruin-validate: ## Validate the bruin pipeline configuration
	docker compose run --rm bruin validate /workspace/bruin_pipeline

seed-raw: ## Insert a small synthetic dataset into raw.cars (for testing transforms)
	docker compose run --rm --entrypoint python scrapy scripts/seed_raw_cars.py

smoke-pipeline: ## Smoke-test the Scrapy item pipeline (no live site needed)
	docker compose run --rm --entrypoint python scrapy scripts/smoke_test_pipeline.py

smoke-parse: ## Smoke-test CarsSpider.parse_car_page against a synthetic detail page (no live site needed)
	docker compose run --rm --entrypoint python scrapy scripts/smoke_test_spider_parse.py

smoke-import-historical: ## Smoke-test scripts/import_historical_fact.py end-to-end (writes/cleans temp rows)
	docker compose run --rm --entrypoint python scrapy scripts/smoke_test_historical_import.py

# Append a historical fact-table CSV onto marts.fact_car_listings.
# WARNING: NOT idempotent. Each run appends another full copy of the CSV --
# fact_car_listings has a surrogate id PK and no natural-key dedup. To
# re-import, first run `make full-refresh` (rebuilds the fact from staging)
# or TRUNCATE marts.fact_car_listings manually.
# CSV path is relative to the repo root; the scrapy container already bind-mounts
# the repo at /app, so `data/foo.csv` on the host becomes `/app/data/foo.csv` inside.
CSV ?= data/historical_fact.csv
import-historical: ## One-shot append historical rows to marts.fact_car_listings (CSV=path/to/file.csv)
	docker compose run --rm --entrypoint python scrapy scripts/import_historical_fact.py --csv $(CSV)

migrate: ## Apply pending sql/migrations/*.sql against the running postgres (idempotent)
	@for f in $$(ls sql/migrations/*.sql 2>/dev/null | sort); do \
	    echo "==> Applying $$f"; \
	    docker compose exec -T postgres psql -U $${POSTGRES_USER:-cars} -d $${POSTGRES_DB:-cars} -v ON_ERROR_STOP=1 < $$f || exit 1; \
	done

clean: ## Stop containers and delete volumes (DESTROYS data)
	docker compose down -v
