ACTIONLINT_IMAGE := rhysd/actionlint:1.7.12@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667
ZIZMOR_IMAGE := ghcr.io/zizmorcore/zizmor:1.33.1@sha256:ecd3ffe6158de1322e05a044ed43749bee12b1dccb7e1a7859bc6ac4b2a1c516
DOCKER_RUN := docker run --rm -v "$(CURDIR):/repo:ro" -w /repo
SHELL_SCRIPTS = $(shell git ls-files '*.sh')

.PHONY: help lint actionlint shellcheck zizmor pinning

help: ## Show available targets
	@grep -E '^[a-z.-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "%-12s %s\n", $$1, $$2}'

lint: actionlint shellcheck zizmor pinning ## Run every static check

actionlint: ## Lint workflows (embedded shellcheck on run: blocks)
	$(DOCKER_RUN) $(ACTIONLINT_IMAGE) -color

shellcheck: ## Lint standalone shell scripts
	$(DOCKER_RUN) --entrypoint shellcheck $(ACTIONLINT_IMAGE) $(SHELL_SCRIPTS)

zizmor: ## Audit workflows for security issues (online audits need GH_TOKEN)
	$(DOCKER_RUN) $(if $(GH_TOKEN),-e GH_TOKEN,) $(ZIZMOR_IMAGE) $(if $(GH_TOKEN),,--offline) .

pinning: ## Check that third-party actions are pinned by SHA
	bash .github/scripts/check-pinned-actions.sh
	bash .github/scripts/check-pinned-actions.sh tests/fixtures/pinning/pinned
	if bash .github/scripts/check-pinned-actions.sh tests/fixtures/pinning/unpinned >/dev/null; then \
		echo "Unpinned fixture was not rejected"; exit 1; \
	fi
