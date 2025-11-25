# Makefile for managing n8n Docker stack

# Configuration
IMAGE ?= n8nio/n8n:latest
# Base directory where installer placed all files
BASE_DIR ?= /opt/n8n

# Docker compose command with optional sudo fallback
DCOMPOSE = docker compose
DCOMPOSE_SUDO = sudo docker compose

.PHONY: up down restart logs update

up:
	@echo "🚀 Starting n8n stack..."
	@cd $(BASE_DIR) && $(DCOMPOSE) up -d || (cd $(BASE_DIR) && $(DCOMPOSE_SUDO) up -d)

down:
	@echo "🛑 Stopping n8n stack..."
	@cd $(BASE_DIR) && $(DCOMPOSE) down || (cd $(BASE_DIR) && $(DCOMPOSE_SUDO) down)

restart: down up

logs:
	@echo "📜 Showing logs (follow)..."
	@cd $(BASE_DIR) && $(DCOMPOSE) logs -f || (cd $(BASE_DIR) && $(DCOMPOSE_SUDO) logs -f)

update:
	@echo "🔄 Updating n8n image and restarting stack..."
	@cd $(BASE_DIR) && $(DCOMPOSE) pull n8n && $(DCOMPOSE) up -d --force-recreate || (cd $(BASE_DIR) && $(DCOMPOSE_SUDO) pull n8n && $(DCOMPOSE_SUDO) up -d --force-recreate)
