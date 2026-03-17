IMAGE_NAME   := pgagroal
IMAGE_TAG    := 2.0.2
COMPOSE      := docker compose
HELM_RELEASE := pgagroal
HELM_CHART   := helm/pgagroal
NAMESPACE    := pgagroal

.PHONY: build run test test-backend-restart test-concurrent test-pooling test-startup-failure test-invalid-creds test-all test-validation test-refresh clean stop logs helm-lint helm-template helm-install helm-upgrade helm-uninstall refresh refresh-dry-run prepare-release release-check

# ---------------------------------------------------------------------------
# Docker
# ---------------------------------------------------------------------------

## build     : Build the pgagroal container image
build:
	docker build -t $(IMAGE_NAME):$(IMAGE_TAG) .

## run       : Start the full stack (postgres + pgagroal)
run: build
	$(COMPOSE) up -d postgres pgagroal
	@echo "pgagroal listening on localhost:6432"

## test      : Build and run the integration test
test:
	bash test/integration/container-start-test.sh

## test-backend-restart : Test pgagroal recovery after backend restart
test-backend-restart:
	bash test/resilience/backend-restart-test.sh

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

## test-validation : Run validation tests
test-validation: test-pooling test-startup-failure test-invalid-creds

## test-all  : Run every test sequentially
test-all: test test-backend-restart test-concurrent test-validation

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
		--set credentials.username=testuser \
		--set credentials.password=testpass \
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
