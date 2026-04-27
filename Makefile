SHELL := /bin/bash

# Ensure .env exists so docker compose --env-file substitutions don't blow up.
ifeq (,$(wildcard .env))
$(warning .env not found -- copy .env.example to .env before running targets that need it)
endif

.PHONY: help up down restart logs ps psql scrape shell-scrapy transform bruin-validate seed-raw smoke-pipeline build clean

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

transform: ## Run the bruin pipeline (expects bruin_pipeline/ to have assets)
	docker compose run --rm bruin run /workspace/bruin_pipeline

bruin-validate: ## Validate the bruin pipeline configuration
	docker compose run --rm bruin validate /workspace/bruin_pipeline

seed-raw: ## Insert a small synthetic dataset into raw.cars (for testing transforms)
	docker compose run --rm --entrypoint python scrapy scripts/seed_raw_cars.py

smoke-pipeline: ## Smoke-test the Scrapy item pipeline (no live site needed)
	docker compose run --rm --entrypoint python scrapy scripts/smoke_test_pipeline.py

clean: ## Stop containers and delete volumes (DESTROYS data)
	docker compose down -v
