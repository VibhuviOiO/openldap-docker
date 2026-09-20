# OpenLDAP Docker Makefile
# Common operations for development and testing

.PHONY: help build run stop logs shell test test-all clean clean-all
.PHONY: lint validate backup restore ldapcheck ci-local
.PHONY: test-integration test-replication

# Default variables
IMAGE_NAME ?= openldap
IMAGE_TAG ?= latest
CONTAINER_NAME ?= openldap
DOMAIN ?= example.com
ADMIN_PASSWORD ?= admin
SERVER_ID ?= 1

# Derive the suffix from DOMAIN unless explicitly overridden.
comma := ,
SUFFIX ?= dc=$(subst .,$(comma),$(DOMAIN))
TIMESTAMP := $(shell date +%Y%m%d-%H%M%S)
BACKUP_DIR ?= backup

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
	@echo "$(YELLOW)Initialisation can take up to ~90s before the port is serving.$(RESET)"

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
# NOTE: Integration use-cases are maintained in the separate openldap-usecases repository.
# Run them from the sibling directory (e.g., ../openldap-usecases/<use-case>/test.sh).
test-all:
	@echo "$(YELLOW)Integration use-cases are maintained in the openldap-usecases repository.$(RESET)"
	@echo "Run individual tests from ../openldap-usecases/<use-case>/ (e.g. ./test.sh)."
	@exit 0

## clean: Remove containers, volumes, and images
clean: stop
	@echo "$(BLUE)Cleaning up...$(RESET)"
	-docker volume rm ldap-data ldap-config ldap-logs 2>/dev/null || true
	-docker rmi $(IMAGE_NAME):$(IMAGE_TAG) 2>/dev/null || true
	@echo "$(GREEN)✓ Cleanup complete$(RESET)"

## clean-all: Clean all use-case containers and volumes
# NOTE: Use-cases are maintained in the separate openldap-usecases repository.
clean-all: clean
	@echo "$(YELLOW)Use-case cleanup is handled in the openldap-usecases repository.$(RESET)"
	@echo "Use docker compose down -v in ../openldap-usecases/<use-case>/ as needed."
	@exit 0

## lint: Run all linters (hadolint, shellcheck) and fail on findings
lint:
	@echo "$(BLUE)Running linters...$(RESET)"
	@echo "$(YELLOW)- Dockerfile (hadolint)$(RESET)"
	@if command -v hadolint >/dev/null 2>&1; then \
		hadolint Dockerfile || exit 1; \
	else \
		echo "  hadolint not installed, skipping"; \
	fi
	@echo "$(YELLOW)- Shell scripts (shellcheck)$(RESET)"
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck startup.sh scripts/*.sh || exit 1; \
	else \
		echo "  shellcheck not installed, skipping"; \
	fi
	@echo "$(GREEN)✓ Linting complete$(RESET)"

## validate: Validate root docker-compose file
validate:
	@echo "$(BLUE)Validating docker-compose files...$(RESET)"
	@docker compose config >/dev/null 2>&1 && echo "$(GREEN)✓ Root compose valid$(RESET)" \
		|| (echo "$(RED)✗ Root compose invalid$(RESET)" && exit 1)
	@echo "$(YELLOW)Use-case compose files are validated in the sibling openldap-usecases repository.$(RESET)"

## backup: Back up both the data and the cn=config database into backup/<timestamp>/
# The data LDIF alone is not a backup: it does not contain ACLs, overlays,
# indices or the replication configuration, so a node cannot be rebuilt from it.
backup:
	@echo "$(BLUE)Creating backup...$(RESET)"
	@mkdir -p "$(BACKUP_DIR)/$(TIMESTAMP)"
	@docker exec $(CONTAINER_NAME) slapcat -b "$(SUFFIX)" > "$(BACKUP_DIR)/$(TIMESTAMP)/data.ldif" \
		|| (echo "$(RED)✗ Data backup failed (is $(CONTAINER_NAME) running?)$(RESET)" && exit 1)
	@docker exec $(CONTAINER_NAME) slapcat -b cn=config > "$(BACKUP_DIR)/$(TIMESTAMP)/config.ldif" \
		|| (echo "$(RED)✗ Config backup failed$(RESET)" && exit 1)
	@printf 'SUFFIX=%s\nSERVER_ID=%s\nDOMAIN=%s\n' "$(SUFFIX)" "$(SERVER_ID)" "$(DOMAIN)" \
		> "$(BACKUP_DIR)/$(TIMESTAMP)/meta.env"
	@echo "$(GREEN)✓ Backup written to $(BACKUP_DIR)/$(TIMESTAMP)/$(RESET)"
	@echo "  data.ldif, config.ldif, meta.env"

## restore: DESTRUCTIVE restore of data.ldif from a backup directory
# Usage: make restore DIR=backup/20260101-120000 FORCE=1 [SERVER_ID=2]
#
# Why this looks the way it does:
#   * docker exec cannot reach a stopped container, so the restore runs in a
#     throwaway container that inherits the volumes via --volumes-from.
#   * slapd must not be running: slapadd needs exclusive access to the LMDB env.
#   * slapadd requires the -b suffix; without it nothing sensible is restored.
#   * slapadd needs -S <serverID>. Without it, generated entryCSNs carry SID
#     000, which is not a valid SID for multi-provider replication and corrupts
#     the mesh (OpenLDAP 2.6 Administrator's Guide, N-Way Multi-Provider).
restore:
	@if [ -z "$(DIR)" ]; then \
		echo "$(RED)Error: specify the backup directory, e.g. make restore DIR=$(BACKUP_DIR)/20260101-120000 FORCE=1$(RESET)"; \
		exit 1; \
	fi
	@if [ ! -f "$(DIR)/data.ldif" ]; then \
		echo "$(RED)Error: $(DIR)/data.ldif not found$(RESET)"; \
		exit 1; \
	fi
	@if [ "$(FORCE)" != "1" ]; then \
		echo "$(RED)Refusing to run: this DELETES the current database before restoring.$(RESET)"; \
		echo "Re-run with FORCE=1 to confirm."; \
		exit 1; \
	fi
	@docker inspect $(CONTAINER_NAME) >/dev/null 2>&1 \
		|| (echo "$(RED)Error: container $(CONTAINER_NAME) must exist (stopped is fine, removed is not)$(RESET)" && exit 1)
	@echo "$(BLUE)Stopping $(CONTAINER_NAME)...$(RESET)"
	-@docker stop $(CONTAINER_NAME) >/dev/null 2>&1 || true
	@echo "$(BLUE)Restoring data into $(SUFFIX) with SID $(SERVER_ID)...$(RESET)"
	@docker run --rm -i --volumes-from $(CONTAINER_NAME) \
		--entrypoint /bin/bash $(IMAGE_NAME):$(IMAGE_TAG) -c '\
			set -e; \
			rm -f /var/lib/ldap/data.mdb /var/lib/ldap/lock.mdb; \
			slapadd -F /etc/openldap/slapd.d -b "$(SUFFIX)" -S $(SERVER_ID) -l /dev/stdin' \
		< "$(DIR)/data.ldif" \
		|| (echo "$(RED)✗ Restore failed.$(RESET)" && echo "Start the container again with: docker start $(CONTAINER_NAME)" && exit 1)
	@echo "$(GREEN)✓ Data restored.$(RESET)"
	@echo "  Note: cn=config was NOT restored. See $(DIR)/config.ldif and the docs;"
	@echo "  restoring it is a manual, version-sensitive procedure."
	@echo "$(BLUE)Starting $(CONTAINER_NAME)...$(RESET)"
	-@docker start $(CONTAINER_NAME) >/dev/null 2>&1 || true

## ldapcheck: Validate replication configuration and convergence
# Usage: make ldapcheck [CONTAINER_NAME=openldap] [PEERS=node2,node3]
ldapcheck:
	@echo "$(BLUE)Running replication validation...$(RESET)"
	@docker exec $(CONTAINER_NAME) /usr/local/bin/scripts/ldapcheck.sh $(if $(PEERS),--peers "$(PEERS)",) \
		|| (echo "$(RED)✗ Validation reported problems$(RESET)" && exit 1)

## test-integration: Run the single-node integration scenarios against the built image
test-integration:
	@echo "$(BLUE)Running single-node integration scenarios...$(RESET)"
	@bash tests/integration/single-node.sh $(IMAGE_NAME):$(IMAGE_TAG)

## test-replication: Run the 3-node replication integration test against the built image
test-replication:
	@echo "$(BLUE)Running 3-node replication integration test...$(RESET)"
	@bash tests/integration/replication.sh $(IMAGE_NAME):$(IMAGE_TAG)

## ci-local: Run CI validation locally (lint, validate, build, start, test, stop)
ci-local: lint validate build
	@echo "$(BLUE)Starting container for the connectivity test...$(RESET)"
	-@docker rm -f $(CONTAINER_NAME) >/dev/null 2>&1 || true
	@$(MAKE) run
	@echo "$(BLUE)Waiting for initialisation...$(RESET)"
	@ok=0; for i in $$(seq 1 60); do \
		if docker exec $(CONTAINER_NAME) /usr/local/bin/scripts/healthcheck.sh auto >/dev/null 2>&1; then ok=1; break; fi; \
		sleep 3; \
	done; \
	if [ "$$ok" != "1" ]; then echo "$(RED)✗ Container never became healthy$(RESET)"; docker logs $(CONTAINER_NAME) | tail -40; $(MAKE) stop; exit 1; fi
	@$(MAKE) test
	@$(MAKE) ldapcheck
	@$(MAKE) stop
	@echo "$(GREEN)✓ Local CI validation complete$(RESET)"
