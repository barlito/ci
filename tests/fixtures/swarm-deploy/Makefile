APP := ../app
export TRACE_FILE ?= $(CURDIR)/trace.log

.PHONY: deploy.prod deploy.update rollback deploy.recover e2e.fail e2e.hang

deploy.prod deploy.update rollback deploy.recover:
	@./exported-trace.sh $@
	@$(MAKE) --no-print-directory -C $(APP) $@

e2e.fail:
	@./exported-trace.sh $@
	@FAIL_TARGETS=$@ $(APP)/trace.sh $@

e2e.hang:
	@./exported-trace.sh $@
	@sleep 3600
