STACK ?= fixture
REGISTRY ?= localhost:5000
TRACE_FILE ?= $(CURDIR)/trace.log
CONFIG_VERSION := $(shell sha1sum app.conf | cut -c1-12)
export REGISTRY CONFIG_VERSION TRACE_FILE

TRACE = ./trace.sh $@
REQUIRE_TAG = $(if $(TAG),,$(error TAG is required))

.PHONY: deploy.prod deploy.update rollback deploy.recover deploy.ci docker.undeploy.ci fixture.down

deploy.prod:
	$(REQUIRE_TAG)
	$(TRACE)
	docker stack deploy --with-registry-auth --detach=false -c docker-compose-prod.yml $(STACK)

deploy.update:
	$(REQUIRE_TAG)
	$(TRACE)
	docker service update --with-registry-auth --detach=false --image $(REGISTRY)/fixture-app:$(TAG) $(STACK)_app
	docker service update --with-registry-auth --detach=false --image $(REGISTRY)/fixture-worker:$(TAG) $(STACK)_worker

rollback:
	$(REQUIRE_TAG)
	$(TRACE)
	$(MAKE) --no-print-directory deploy.update TAG=$(TAG)

deploy.recover:
	$(TRACE)

deploy.ci:
	$(TRACE)

docker.undeploy.ci:
	$(TRACE)

fixture.down:
	docker stack rm --detach=false $(STACK)
