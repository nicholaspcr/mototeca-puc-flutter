.PHONY: help run build test test-integration migrate db-up db-down db-logs generate

.DEFAULT_GOAL := help

-include .env
export

help: ## List available commands
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "%-10s %s\n", $$1, $$2}'

run: ## Run the API locally
	go run ./cmd/api

build: ## Build the API binary into bin/api
	CGO_ENABLED=0 go build -o bin/api ./cmd/api

test: ## Run backend unit tests (no database required)
	go test ./cmd/... ./internal/...

test-integration: ## Run backend integration tests against $DATABASE_URL (needs `make db-up`)
	go test -tags=integration ./cmd/... ./internal/...

migrate: ## Apply every db/migrations/*.sql to $DATABASE_URL, in order
	@for f in db/migrations/*.sql; do \
		echo "applying $$f"; \
		psql "$$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$$f" >/dev/null || exit 1; \
	done

generate: ## Regenerate Go/TypeScript code from proto/**/*.proto
	buf generate

db-up: ## Start the local Postgres container and wait until it accepts connections
	docker compose up -d --wait db
	@until pg_isready -h 127.0.0.1 -p 5432 -U user -d mototeca >/dev/null 2>&1; do sleep 0.5; done

db-down: ## Stop the local Postgres container
	docker compose down

db-logs: ## Tail the Postgres container logs
	docker compose logs -f db
