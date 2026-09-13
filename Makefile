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

migrate: ## Apply pending db/migrations/*.sql to $DATABASE_URL (docker compose up does this too)
	sh scripts/migrate.sh

generate: ## Regenerate Go/TypeScript code from proto/**/*.proto
	buf generate

db-up: ## Start the local Postgres container and wait until it accepts connections
	docker compose up -d --wait db
	@until pg_isready -h 127.0.0.1 -p 5432 -U user -d mototeca >/dev/null 2>&1; do sleep 0.5; done

db-down: ## Stop the local Postgres container
	docker compose down

db-logs: ## Tail the Postgres container logs
	docker compose logs -f db

e2e: ## Smoke-test the API end to end inside the compose network (needs `docker compose up -d api`)
	docker run --rm --network mototeca_default \
		-v "$$PWD/scripts/e2e.sh:/e2e.sh:ro" curlimages/curl:latest sh /e2e.sh

test-integration-docker: ## Run integration tests inside the compose network (works when the host can't reach the db port)
	docker run --rm --network mototeca_default \
		-v "$$PWD":/src -w /src -v mototeca-gocache:/go/pkg/mod \
		-e DATABASE_URL=postgres://user:password@db:5432/mototeca?sslmode=disable \
		golang:1.27-alpine go test -tags=integration ./internal/...
