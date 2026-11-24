APP := ../app
export TRACE_FILE ?= $(CURDIR)/trace.log

.PHONY: deploy.prod deploy.update rollback deploy.recover e2e.fail

deploy.prod deploy.update rollback deploy.recover:
	@./exported-trace.sh $@
	@$(MAKE) --no-print-directory -C $(APP) $@

e2e.fail:
	@./exported-trace.sh $@
	@FAIL_TARGETS=$@ $(APP)/trace.sh $@
