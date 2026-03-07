# OpenLDAP Docker Makefile
# Common operations for development and testing

.PHONY: help build run stop logs shell test clean test-all

# Default variables
IMAGE_NAME ?= openldap
IMAGE_TAG ?= latest
CONTAINER_NAME ?= openldap
DOMAIN ?= example.com
ADMIN_PASSWORD ?= admin

# Colors for output
BLUE := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
RESET := \033[0m

## help: Show this help message
help:
	@echo "OpenLDAP Docker - Available Commands:"
	@echo ""
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## //g' | column -t -s ':' | sed 's/^/  /'
	@echo ""

## build: Build the Docker image
build:
	@echo "$(BLUE)Building OpenLDAP image...$(RESET)"
	docker build -t $(IMAGE_NAME):$(IMAGE_TAG) .
	@echo "$(GREEN)✓ Build complete$(RESET)"

## run: Start single-node OpenLDAP container
run:
	@echo "$(BLUE)Starting OpenLDAP container...$(RESET)"
	docker run -d \
		--name $(CONTAINER_NAME) \
		-e LDAP_DOMAIN=$(DOMAIN) \
		-e LDAP_ADMIN_PASSWORD=$(ADMIN_PASSWORD) \
		-p 389:389 \
		-v ldap-data:/var/lib/ldap \
		-v ldap-config:/etc/openldap/slapd.d \
		$(IMAGE_NAME):$(IMAGE_TAG)
	@echo "$(GREEN)✓ Container started$(RESET)"
	@echo "$(YELLOW)Wait 10 seconds for initialization...$(RESET)"
	@sleep 10
	@docker logs $(CONTAINER_NAME) 2>&1 | tail -5

## stop: Stop and remove the container
stop:
	@echo "$(BLUE)Stopping OpenLDAP container...$(RESET)"
	-docker stop $(CONTAINER_NAME) 2>/dev/null
	-docker rm $(CONTAINER_NAME) 2>/dev/null
	@echo "$(GREEN)✓ Container stopped$(RESET)"

## logs: Tail container logs
logs:
	@docker logs -f $(CONTAINER_NAME) 2>&1 || echo "$(RED)Container not running$(RESET)"

## shell: Open shell in running container
shell:
	@docker exec -it $(CONTAINER_NAME) /bin/bash || echo "$(RED)Container not running$(RESET)"

## test: Run basic connectivity test
test:
	@echo "$(BLUE)Running basic connectivity test...$(RESET)"
	@docker exec $(CONTAINER_NAME) /usr/local/bin/scripts/test-basic.sh localhost 389 \
		&& echo "$(GREEN)✓ Tests passed$(RESET)" \
		|| (echo "$(RED)✗ Tests failed$(RESET)" && exit 1)

## test-all: Run all integration tests
test-all:
	@echo "$(BLUE)Running integration test suite...$(RESET)"
	@echo "$(YELLOW)1. Testing overlay features...$(RESET)"
	@cd use-cases/overlay-features && docker-compose up -d && sleep 15
	@docker logs openldap-overlays 2>&1 | grep -q "All overlay tests PASSED" \
		&& echo "$(GREEN)✓ Overlay tests passed$(RESET)" \
		|| (echo "$(RED)✗ Overlay tests failed$(RESET)" && exit 1)
	@cd use-cases/overlay-features && docker-compose down -v
	@echo "$(YELLOW)2. Testing TLS...$(RESET)"
	@cd use-cases/tls-enabled && docker-compose up -d && sleep 10
	@LDAPTLS_REQCERT=never ldapsearch -x -H ldaps://localhost:636 \
		-D "cn=Manager,dc=example,dc=com" -w "AdminPass123!" \
		-b "dc=example,dc=com" -s base >/dev/null 2>&1 \
		&& echo "$(GREEN)✓ TLS tests passed$(RESET)" \
		|| (echo "$(RED)✗ TLS tests failed$(RESET)" && exit 1)
	@cd use-cases/tls-enabled && docker-compose down -v
	@echo "$(YELLOW)3. Testing idempotency...$(RESET)"
	@cd use-cases/idempotency-test && docker-compose up -d && sleep 10
	@docker restart openldap-idempotency && sleep 10
	@docker logs openldap-idempotency 2>&1 | grep -q "already configured" \
		&& echo "$(GREEN)✓ Idempotency tests passed$(RESET)" \
		|| (echo "$(RED)✗ Idempotency tests failed$(RESET)" && exit 1)
	@cd use-cases/idempotency-test && docker-compose down -v
	@echo "$(GREEN)✓ All integration tests passed!$(RESET)"

## clean: Remove containers, volumes, and images
clean: stop
	@echo "$(BLUE)Cleaning up...$(RESET)"
	-docker volume rm ldap-data ldap-config ldap-logs 2>/dev/null || true
	-docker rmi $(IMAGE_NAME):$(IMAGE_TAG) 2>/dev/null || true
	@echo "$(GREEN)✓ Cleanup complete$(RESET)"

## clean-all: Clean all use-case containers and volumes
clean-all: clean
	@echo "$(BLUE)Cleaning all use-cases...$(RESET)"
	@for dir in use-cases/*/; do \
		if [ -f "$$dir/docker-compose.yml" ]; then \
			echo "Cleaning $$dir..."; \
			(cd "$$dir" && docker-compose down -v 2>/dev/null) || true; \
		fi \
	done
	@echo "$(GREEN)✓ All use-cases cleaned$(RESET)"

## lint: Run all linters (hadolint, shellcheck)
lint:
	@echo "$(BLUE)Running linters...$(RESET)"
	@echo "$(YELLOW)- Dockerfile (hadolint)$(RESET)"
	@which hadolint >/dev/null 2>&1 && hadolint Dockerfile || echo "$(YELLOW)hadolint not installed, skipping$(RESET)"
	@echo "$(YELLOW)- Shell scripts (shellcheck)$(RESET)"
	@which shellcheck >/dev/null 2>&1 && shellcheck scripts/*.sh || echo "$(YELLOW)shellcheck not installed, skipping$(RESET)"
	@echo "$(GREEN)✓ Linting complete$(RESET)"

## validate: Validate docker-compose files
validate:
	@echo "$(BLUE)Validating docker-compose files...$(RESET)"
	@docker-compose config >/dev/null 2>&1 && echo "$(GREEN)✓ Root compose valid$(RESET)" || echo "$(RED)✗ Root compose invalid$(RESET)"
	@for dir in use-cases/*/; do \
		if [ -f "$$dir/docker-compose.yml" ]; then \
			docker-compose -f "$$dir/docker-compose.yml" config >/dev/null 2>&1 \
			&& echo "$(GREEN)✓ $$dir valid$(RESET)" \
			|| echo "$(RED)✗ $$dir invalid$(RESET)"; \
		fi \
	done

## backup: Backup LDAP data to backup/ directory
backup:
	@echo "$(BLUE)Creating backup...$(RESET)"
	@mkdir -p backup
	@docker exec $(CONTAINER_NAME) slapcat -b "dc=$$(echo $(DOMAIN) | sed 's/\./,dc=/g')" > backup/ldap-backup-$$(date +%Y%m%d-%H%M%S).ldif 2>/dev/null \
		&& echo "$(GREEN)✓ Backup created in backup/$(RESET)" \
		|| (echo "$(RED)✗ Backup failed$(RESET)" && exit 1)

## restore: Restore LDAP data from backup file (use: make restore FILE=backup/xxx.ldif)
restore:
	@if [ -z "$(FILE)" ]; then \
		echo "$(RED)Error: Specify backup file with FILE=path/to/backup.ldif$(RESET)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Restoring from $(FILE)...$(RESET)"
	@docker exec -i $(CONTAINER_NAME) slapadd -F /etc/openldap/slapd.d < $(FILE) \
		&& echo "$(GREEN)✓ Restore complete$(RESET)" \
		|| (echo "$(RED)✗ Restore failed$(RESET)" && exit 1)

## ci-local: Run CI validation locally (requires docker and tools)
ci-local: lint validate build test
	@echo "$(GREEN)✓ Local CI validation complete$(RESET)"
