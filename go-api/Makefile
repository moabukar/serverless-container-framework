.PHONY: help build run test docker-build docker-run dev deploy deploy-debug remove clean

help: ## Show this help
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

build: ## Build Go binary
	go build -o main main.go

run: ## Run locally (native)
	go run main.go

test: ## Test endpoints
	@echo "Testing health endpoint..."
	@curl -s http://localhost:8080/health | jq .
	@echo "\nTesting API endpoint..."
	@curl -s http://localhost:8080/api/hello | jq .
	@echo "\nTesting users endpoint..."
	@curl -s http://localhost:8080/api/users | jq .

docker-build: ## Build Docker image
	docker build -t golang-serverless-demo .

docker-run: docker-build ## Run Docker container
	docker run -p 8080:8080 -e COMPUTE_TYPE=docker golang-serverless-demo

compose-up: ## Start with docker-compose
	docker compose up --build

compose-down: ## Stop docker-compose
	docker compose down

dev: ## Start serverless dev mode (local ALB emulation)
	serverless dev

deploy: ## Deploy to AWS
	serverless deploy

deploy-debug: ## Deploy with debug logs
	serverless deploy --debug

deploy-lambda: ## Deploy only Lambda container
	serverless deploy --container api-lambda

deploy-fargate: ## Deploy only Fargate container
	serverless deploy --container api-fargate

remove: ## Remove deployment (keep VPC)
	serverless remove

remove-all: ## Remove everything including VPC
	serverless remove --force

clean: ## Clean build artifacts
	rm -f main
	rm -rf .serverless/
	rm -rf .build/

logs-lambda: ## Tail Lambda logs
	serverless logs --container api-lambda --tail

logs-fargate: ## Tail Fargate logs
	serverless logs --container api-fargate --tail