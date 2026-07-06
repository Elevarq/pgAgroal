IMAGE_NAME   := pgagroal
IMAGE_TAG    := 2.1.0
COMPOSE      := docker compose
HELM_RELEASE := pgagroal
HELM_CHART   := helm/pgagroal
NAMESPACE    := pgagroal

.PHONY: build run test test-backend-restart test-docker-restart test-concurrent test-pooling test-startup-failure test-invalid-creds test-hba test-hardened test-all test-validation test-refresh test-release-checks security clean stop logs helm-lint helm-template helm-install helm-upgrade helm-uninstall refresh refresh-dry-run prepare-release release-check

# ---------------------------------------------------------------------------
# Docker
# ---------------------------------------------------------------------------

## build     : Build the pgagroal container image
build:
	docker build -t $(IMAGE_NAME):$(IMAGE_TAG) .

## run       : Start the full stack (postgres + pgagroal)
# Compose interpolates credentials from the environment fail-fast (no
# committed defaults — see .env.example). First run generates an
# ephemeral .env so local development keeps working out of the box.
run: build
	@if [ ! -f .env ]; then \
		umask 177; \
		{ echo "POSTGRES_PASSWORD=$$(openssl rand -hex 16)"; \
		  echo "PGEXPORTER_PASSWORD=$$(openssl rand -hex 16)"; } > .env; \
		echo "Generated .env with ephemeral credentials (see .env.example)"; \
	fi
	$(COMPOSE) up -d postgres pgagroal
	@echo "pgagroal listening on localhost:6432"

## test      : Build and run the integration test
test:
	bash test/integration/container-start-test.sh

## test-backend-restart : Test pgagroal recovery after backend restart
test-backend-restart:
	bash test/resilience/backend-restart-test.sh

## test-docker-restart : Test container recovery after SIGKILL + docker start (stale PID file)
test-docker-restart:
	bash test/resilience/docker-restart-test.sh

## test-concurrent : Test concurrent connections (default 20, override: make test-concurrent CONCURRENCY=50)
test-concurrent:
	bash test/resilience/concurrent-connection-test.sh $(CONCURRENCY)

## test-pooling : Validate connection pooling behavior
test-pooling:
	bash test/validation/pooling-behavior-test.sh

## test-startup-failure : Test behavior when backend is unavailable at startup
test-startup-failure:
	bash test/resilience/startup-failure-test.sh

## test-invalid-creds : Test behavior with wrong credentials
test-invalid-creds:
	bash test/validation/invalid-credentials-test.sh

## test-hba  : Test HBA source-address restriction (dockerless)
test-hba:
	bash test/validation/hba-source-test.sh

## test-hardened : Test network/bind hardened defaults (needs helm; dockerless)
test-hardened:
	bash test/validation/hardened-defaults-test.sh

## test-validation : Run validation tests
test-validation: test-pooling test-startup-failure test-invalid-creds test-hba test-hardened

## test-all  : Run every test sequentially
test-all: test test-backend-restart test-docker-restart test-concurrent test-validation

## stop      : Stop all services
stop:
	$(COMPOSE) down -v

## clean     : Remove containers, volumes, and built image
clean:
	$(COMPOSE) down -v --rmi local --remove-orphans 2>/dev/null || true
	docker rmi $(IMAGE_NAME):$(IMAGE_TAG) 2>/dev/null || true

## logs      : Tail service logs
logs:
	$(COMPOSE) logs -f pgagroal

# ---------------------------------------------------------------------------
# Helm / Kubernetes
# ---------------------------------------------------------------------------

## helm-lint : Lint the Helm chart
helm-lint:
	helm lint $(HELM_CHART)

## helm-template : Render templates locally (dry-run)
helm-template:
	helm template $(HELM_RELEASE) $(HELM_CHART) \
		--set postgresql.host=pg-host

## helm-install : Install the chart into the current cluster
helm-install:
	helm install $(HELM_RELEASE) $(HELM_CHART) \
		-n $(NAMESPACE) --create-namespace

## helm-upgrade : Upgrade an existing release
helm-upgrade:
	helm upgrade $(HELM_RELEASE) $(HELM_CHART) -n $(NAMESPACE)

## helm-uninstall : Remove the Helm release
helm-uninstall:
	helm uninstall $(HELM_RELEASE) -n $(NAMESPACE)

# ---------------------------------------------------------------------------
# Upstream refresh & release
# ---------------------------------------------------------------------------

## refresh         : Refresh pgagroal upstream version (requires VERSION=x.y.z)
refresh:
	@test -n "$(VERSION)" || { echo "Usage: make refresh VERSION=x.y.z"; exit 1; }
	bash scripts/refresh-pgagroal.sh --version $(VERSION)

## refresh-dry-run : Show what a refresh would change (requires VERSION=x.y.z)
refresh-dry-run:
	@test -n "$(VERSION)" || { echo "Usage: make refresh-dry-run VERSION=x.y.z"; exit 1; }
	bash scripts/refresh-pgagroal.sh --version $(VERSION) --dry-run

## prepare-release : Verify consistency and print release commands
prepare-release:
	bash scripts/prepare-release.sh

## release-check  : Quick consistency check (non-interactive)
release-check:
	bash scripts/prepare-release.sh --check-only

## test-refresh    : Run refresh script automated tests
test-refresh:
	bash test/refresh/test-refresh.sh

## test-release-checks : Run prepare-release.sh Gate F automated tests
test-release-checks:
	bash test/release-checks/test-prepare-release.sh

## security : Run local security and supply-chain checks
security:
	bash scripts/security-checks.sh all
