# Makefile for managing n8n Docker container

# Configuration
IMAGE ?= n8nio/n8n:latest
CONTAINER_NAME ?= n8n
# Directory where n8n stores its data (adjust if needed)
DATA_DIR ?= /opt/n8n

# Docker run options (customise if you need env vars, ports, etc.)
DOCKER_RUN_OPTS ?= -p 5678:5678 -v $(DATA_DIR):/root/.n8n

.PHONY: up down restart logs update

up:
	@echo "🚀 Starting n8n container..."
	docker run -d --name $(CONTAINER_NAME) $(DOCKER_RUN_OPTS) $(IMAGE)

down:
	@echo "🛑 Stopping and removing n8n container..."
	docker stop $(CONTAINER_NAME) && docker rm $(CONTAINER_NAME)

restart: down up

logs:
	@echo "📜 Showing logs (follow)..."
	docker logs -f $(CONTAINER_NAME)

update:
	@echo "🔄 Updating n8n image and restarting container..."
	docker pull $(IMAGE)
	$(MAKE) restart
