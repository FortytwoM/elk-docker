.DEFAULT_GOAL := help
COMPOSE := docker compose

.PHONY: help up up-mon down restart build clean logs status ps certs setup

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

up: ## Start the core stack (Elasticsearch, Kibana, Logstash, Fleet)
	$(COMPOSE) up -d --build

up-mon: ## Start the stack with monitoring (adds Metricbeat, Filebeat, Heartbeat)
	$(COMPOSE) --profile monitoring up -d --build

down: ## Stop all services
	$(COMPOSE) --profile monitoring down

restart: ## Restart all running services
	$(COMPOSE) restart

build: ## Rebuild all images
	$(COMPOSE) --profile monitoring build

clean: ## Stop and remove everything (containers, volumes, images)
	$(COMPOSE) --profile monitoring down -v --rmi local
	rm -rf tls/certs/*/

logs: ## Tail logs from all running services
	$(COMPOSE) logs -f --tail=100

status: ## Show service health and status
	@$(COMPOSE) ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

ps: status ## Alias for status

certs: ## Regenerate TLS certificates (also resets Kibana config for new CA fingerprint)
	rm -rf tls/certs/*/
	docker volume ls -q --filter name=kibana-config | xargs -r docker volume rm 2>/dev/null || true
	$(COMPOSE) up tls

setup: ## Re-run user/role setup
	$(COMPOSE) up setup
