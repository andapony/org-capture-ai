.PHONY: test test-regression test-error test-integration clean deps help

EMACS ?= emacs
GPTEL_DIR = test-deps/gptel

help:
	@echo "org-capture-ai development targets"
	@echo ""
	@echo "  make test             Run all test suites"
	@echo "  make test-regression  Run regression tests only"
	@echo "  make test-error       Run error condition tests only"
	@echo "  make test-integration Run integration tests only"
	@echo "  make deps             Install gptel test dependency"
	@echo "  make clean            Remove test result logs"
	@echo "  make check            Byte-compile org-capture-ai.el (warnings = errors)"
	@echo ""
	@echo "  EMACS=$(EMACS)"

test:
	./run-tests.sh all

test-regression:
	./run-tests.sh regression

test-error:
	./run-tests.sh error

test-integration:
	./run-tests.sh integration

check:
	@output=$$($(EMACS) --batch --no-site-file \
		-L . \
		-L $(GPTEL_DIR) \
		-f batch-byte-compile \
		org-capture-ai.el 2>&1); \
	filtered=$$(echo "$$output" | grep -v "site-start\|file-missing\|debian\|mapbacktrace\|debug-early\|normal-top-level\|command-line\|#f(compiled"); \
	test -n "$$filtered" && echo "$$filtered" || true; \
	rm -f org-capture-ai.elc; \
	if echo "$$filtered" | grep -q " Error:"; then \
		echo "Byte-compile FAILED."; exit 1; \
	else \
		echo "Byte-compile clean."; \
	fi

deps:
	@if [ -d "$(GPTEL_DIR)" ]; then \
		echo "gptel already present at $(GPTEL_DIR)"; \
	else \
		git clone https://github.com/karthink/gptel.git $(GPTEL_DIR); \
	fi

clean:
	rm -f test-results-*.log org-capture-ai.elc
