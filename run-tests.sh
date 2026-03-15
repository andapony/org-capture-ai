#!/bin/bash
# run-tests.sh - Run all org-capture-ai tests

set -e          # Exit on error
set -o pipefail # Propagate pipeline failures (so `emacs ... | tee` reports emacs exit code)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Default test suite
TEST_SUITE="${1:-all}"

echo "========================================"
echo "org-capture-ai Test Runner"
echo "========================================"
echo

# Function to run a test file
run_test_file() {
    local test_file="$1"
    local test_name="$(basename "$test_file" .el)"

    echo -e "${YELLOW}Running: $test_name${NC}"

    if emacs --batch --no-site-file \
        -L . \
        -L test-deps/gptel \
        -l "$test_file" \
        -f ert-run-tests-batch-and-exit 2>&1 | tee "test-results-$test_name.log"; then
        echo -e "${GREEN}✓ $test_name PASSED${NC}"
        return 0
    else
        echo -e "${RED}✗ $test_name FAILED${NC}"
        echo "  See test-results-$test_name.log for details"
        return 1
    fi
    echo
}

# Function to check for gptel dependency
check_dependencies() {
    if [ ! -d "test-deps/gptel" ]; then
        echo -e "${RED}Error: gptel test dependency not found${NC}"
        echo "Please install gptel to test-deps/gptel/"
        echo
        echo "You can clone it with:"
        echo "  git clone https://github.com/karthink/gptel.git test-deps/gptel"
        exit 1
    fi
}

# Check dependencies
check_dependencies

# Track results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Run tests based on suite
case "$TEST_SUITE" in
    all)
        echo "Running all test suites..."
        echo

        for test_file in org-capture-ai-regression-test.el \
                        org-capture-ai-error-test.el \
                        org-capture-ai-integration-test-v2.el \
                        org-capture-ai-fetch-test.el; do
            TOTAL_TESTS=$((TOTAL_TESTS + 1))
            if run_test_file "$test_file"; then
                PASSED_TESTS=$((PASSED_TESTS + 1))
            else
                FAILED_TESTS=$((FAILED_TESTS + 1))
            fi
        done
        ;;

    regression)
        echo "Running regression tests only..."
        echo
        run_test_file "org-capture-ai-regression-test.el"
        ;;

    error)
        echo "Running error condition tests only..."
        echo
        run_test_file "org-capture-ai-error-test.el"
        ;;

    integration)
        echo "Running integration tests only..."
        echo
        run_test_file "org-capture-ai-integration-test-v2.el"
        ;;

    fetch)
        echo "Running fetch tests only..."
        echo
        run_test_file "org-capture-ai-fetch-test.el"
        ;;

    legacy)
        echo "Running legacy integration tests..."
        echo
        run_test_file "org-capture-ai-integration-test.el"
        ;;

    *)
        echo -e "${RED}Error: Unknown test suite '$TEST_SUITE'${NC}"
        echo
        echo "Usage: $0 [all|regression|error|integration|legacy]"
        echo
        echo "Test suites:"
        echo "  all         - Run all test suites (default)"
        echo "  regression  - Run regression tests for specific bugs"
        echo "  error       - Run error condition tests"
        echo "  integration - Run integration tests (v2)"
        echo "  fetch       - Run real HTTP fetch tests (requires Python 3)"
        echo "  legacy      - Run original integration tests"
        exit 1
        ;;
esac

# Summary
echo
echo "========================================"
echo "Test Summary"
echo "========================================"
if [ "$TEST_SUITE" = "all" ]; then
    echo "Total suites: $TOTAL_TESTS"
    echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
    if [ $FAILED_TESTS -gt 0 ]; then
        echo -e "${RED}Failed: $FAILED_TESTS${NC}"
        echo
        echo "Check test-results-*.log files for details"
        exit 1
    else
        echo
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    fi
else
    echo "Test suite: $TEST_SUITE"
    echo "Check test-results-*.log for details"
fi
