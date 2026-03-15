## Testing org-capture-ai

### Quick Start

Run all tests:
```bash
./run-tests.sh
```

Run specific test suite:
```bash
./run-tests.sh regression    # Regression tests only
./run-tests.sh error         # Error condition tests
./run-tests.sh integration   # Integration tests (v2)
./run-tests.sh fetch         # Real HTTP fetch tests (requires Python 3)
./run-tests.sh legacy        # Original integration tests
```

### Test Organization

```
org-capture-ai/
├── run-tests.sh                           # Test runner script
├── org-capture-ai-test-helpers.el         # Shared test utilities
├── org-capture-ai-regression-test.el      # Tests for specific bugs
├── org-capture-ai-error-test.el           # Error condition tests
├── org-capture-ai-integration-test-v2.el  # Integration tests (new)
├── org-capture-ai-fetch-test.el           # Real HTTP fetch tests
├── org-capture-ai-integration-test.el     # Legacy integration tests
└── test-fixtures/                         # Test data
    ├── html/                              # HTML fixtures
    ├── llm-responses/                     # Mock LLM responses
    └── snapshots/                         # Expected outputs
```

### Test Suites

#### 1. Regression Tests (`org-capture-ai-regression-test.el`)

Tests for specific bugs that were found and fixed. Each test documents:
- What the bug was
- Root cause
- The fix that was applied
- Date and file/line references

**Current regression tests:**
- `org-capture-ai-regression-20251027-multiline-description` - Multi-line DESCRIPTION breaking properties drawer
- `org-capture-ai-regression-20251027-duplicate-processing` - Hook duplication causing double processing
- `org-capture-ai-regression-20251027-heading-replacement` - replace-match destroying heading structure
- `org-capture-ai-regression-unit-sanitize-property-value` - Property value sanitization function
- `org-capture-ai-regression-20260315-duplicate-skip` - Duplicate URL detection with `skip` action
- `org-capture-ai-regression-20260315-duplicate-warn` - Duplicate URL detection with `warn` action
- `org-capture-ai-regression-20260315-takeaways-extracted` - Key takeaways extracted and stored in TAKEAWAYS
- `org-capture-ai-regression-20260315-takeaways-disabled` - Takeaways skipped when `org-capture-ai-extract-takeaways` is nil
- `org-capture-ai-regression-20260315-duplicate-only-matches-completed` - Duplicate check only matches STATUS=completed
- `org-capture-ai-regression-20260315-duplicate-update-continues` - `warn` action still completes processing
- `org-capture-ai-regression-20260315-takeaways-failure-still-completes` - Processing completes even if takeaways LLM call fails

**When to add a regression test:**
Every time you fix a bug, create a regression test that:
1. Reproduces the bug scenario
2. Documents the fix
3. Prevents the bug from recurring

#### 2. Error Condition Tests (`org-capture-ai-error-test.el`)

Tests for error handling and edge cases:
- Network fetch failures (404, timeout, etc.)
- Empty/minimal content (< 50 chars)
- Pages with only scripts/styles
- LLM API failures
- Long descriptions (truncation)
- Special characters and Unicode
- Missing URL property
- Concurrent processing

#### 3. Integration Tests (`org-capture-ai-integration-test-v2.el`)

End-to-end tests of the full capture workflow:
- Complete capture with mocked LLM
- Fixture-based testing
- Multi-line sanitization
- Idempotent setup
- Performance benchmarks

#### 4. Fetch Tests (`org-capture-ai-fetch-test.el`)

Real HTTP fetch tests that spin up a local Python HTTP server and exercise both
fetch methods end-to-end:
- `curl` method: success, missing file (404), connection refused
- `builtin` (`url-retrieve`) method: success, connection refused
- Dispatch function: selecting `curl` vs `builtin` based on `org-capture-ai-fetch-method`

Requires Python 3. Run with `./run-tests.sh fetch`.

#### 5. Legacy Integration Tests (`org-capture-ai-integration-test.el`)

Original integration tests (preserved for compatibility):
- Full capture workflow
- Duplicate processing prevention
- Multi-line sanitization (older version)

### Test Utilities (`org-capture-ai-test-helpers.el`)

Shared utilities for all tests:

**Fixtures:**
- `org-capture-ai-test--load-fixture` - Load HTML/response fixtures
- `org-capture-ai-test--create-temp-org-file` - Create temp test file

**Assertions:**
- `org-capture-ai-test--assert-properties` - Verify org properties
- `org-capture-ai-test--assert-single-properties-drawer` - One drawer per entry
- `org-capture-ai-test--assert-no-orphaned-drawers` - No broken drawer structure
- `org-capture-ai-test--count-properties-drawers` - Count total drawers

**Mocking:**
- `org-capture-ai-test--mock-gptel-request` - Mock LLM calls
- `org-capture-ai-test--mock-fetch-url` - Mock URL fetching
- `org-capture-ai-test--with-mocked-env` - Complete test environment

**Test Flow:**
- `org-capture-ai-test--create-processing-entry` - Create test entry
- `org-capture-ai-test--wait-for-processing` - Wait for async completion
- `org-capture-ai-test--measure-time` - Performance measurement

### Writing New Tests

#### Basic Test Template

```elisp
(ert-deftest my-test-name ()
  "Description of what this tests."
  (org-capture-ai-test--with-mocked-env
   (with-current-buffer (find-file-noselect org-capture-ai-test--temp-file)
     (let* ((marker (org-capture-ai-test--create-processing-entry
                     "https://example.com/test"))
            (entry-pos (marker-position marker)))  ; Save position before processing

       ;; Process the entry
       (org-capture-ai--async-process marker)

       ;; Wait for completion (marker is invalidated after processing)
       (org-capture-ai-test--wait-for-processing marker)

       ;; Navigate back using saved position
       (goto-char entry-pos)
       (org-back-to-heading t)

       ;; Assertions
       (should (equal "completed" (org-entry-get nil "STATUS")))
       (should (= 1 (org-capture-ai-test--count-properties-drawers)))))))
```

#### Using Custom HTML Fixture

```elisp
(ert-deftest my-custom-html-test ()
  "Test with custom HTML fixture."
  (org-capture-ai-test--with-mocked-env
   ;; Load fixture
   (setq org-capture-ai-test--mock-html-response
         (org-capture-ai-test--load-fixture "html" "my-fixture.html"))

   (with-current-buffer (find-file-noselect org-capture-ai-test--temp-file)
     ;; ... test code ...
     )))
```

#### Testing Error Conditions

```elisp
(ert-deftest my-error-test ()
  "Test error handling."
  (org-capture-ai-test--with-mocked-env
   ;; Configure mock to fail
   (setq org-capture-ai-test--mock-fetch-should-fail t)
   (setq org-capture-ai-test--mock-fetch-error-message "My Error")

   (with-current-buffer (find-file-noselect org-capture-ai-test--temp-file)
     (let ((marker (org-capture-ai-test--create-processing-entry
                    "https://example.com/test")))

       (org-capture-ai--async-process marker)
       (org-capture-ai-test--wait-for-processing marker)

       ;; Should be in error state
       (should (equal "fetch-error" (org-entry-get nil "STATUS")))))))
```

### Adding Test Fixtures

1. Create HTML file in `test-fixtures/html/`:
   ```bash
   cat > test-fixtures/html/my-test-case.html <<EOF
   <!DOCTYPE html>
   <html>
   <head><title>Test</title></head>
   <body><p>Content</p></body>
   </html>
   EOF
   ```

2. Load in test:
   ```elisp
   (setq org-capture-ai-test--mock-html-response
         (org-capture-ai-test--load-fixture "html" "my-test-case.html"))
   ```

3. Document in `test-fixtures/README.md`

### Running Tests Interactively

From Emacs:

```elisp
;; Load test file
(load-file "org-capture-ai-regression-test.el")

;; Run all tests in file
(ert-run-tests-interactively "^org-capture-ai-regression-")

;; Run specific test
(ert "org-capture-ai-regression-20251027-multiline-description")

;; Run all tests
(ert t)
```

### Running Tests in Batch Mode

```bash
# Run specific test file
emacs --batch \
  -L . \
  -L test-deps/gptel \
  -l org-capture-ai-regression-test.el \
  -f ert-run-tests-batch-and-exit

# View results
cat test-results-org-capture-ai-regression-test.log
```

### Continuous Integration

To set up CI (GitHub Actions, GitLab CI, etc.):

```yaml
# .github/workflows/test.yml
name: Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: purcell/setup-emacs@master
        with:
          version: 28.2
      - name: Install gptel
        run: git clone https://github.com/karthink/gptel.git test-deps/gptel
      - name: Run tests
        run: ./run-tests.sh
```

### Test-Driven Development Workflow

When fixing a bug or adding a feature:

1. **Write failing test first**
   ```bash
   # Create test that reproduces the issue
   emacs org-capture-ai-regression-test.el
   ```

2. **Verify test fails**
   ```bash
   ./run-tests.sh regression
   # Should fail, confirming it catches the bug
   ```

3. **Implement the fix**
   ```bash
   emacs org-capture-ai.el
   ```

4. **Verify test passes**
   ```bash
   ./run-tests.sh regression
   # Should pass, confirming the fix works
   ```

5. **Run full test suite**
   ```bash
   ./run-tests.sh
   # Ensure no regressions
   ```

### Performance Testing

Measure processing time:

```elisp
(ert-deftest my-perf-test ()
  "Benchmark processing."
  (org-capture-ai-test--with-mocked-env
   (let ((elapsed (org-capture-ai-test--measure-time
                   ;; Code to benchmark
                   (do-something))))
     (message "Elapsed: %.3f seconds" elapsed)
     (should (< elapsed 1.0)))))  ; Assert it's fast enough
```

### Debugging Failed Tests

1. **Check test output:**
   ```bash
   cat test-results-*.log
   ```

2. **Run test interactively:**
   ```elisp
   (load-file "org-capture-ai-regression-test.el")
   (ert "test-name")  ; Step through with debugger
   ```

3. **Enable detailed logging:**
   ```elisp
   (setq org-capture-ai-enable-logging t)
   ;; Check *org-capture-ai-log* buffer
   ```

4. **Inspect test artifacts:**
   ```elisp
   ;; Temp files are cleaned up, but you can disable cleanup:
   (setq org-capture-ai-test--temp-files nil)
   ```

### Coverage Checklist

When adding new features, ensure tests cover:

- ✅ Happy path (normal operation)
- ✅ Error conditions (network failures, invalid input)
- ✅ Edge cases (empty content, special characters, very long values)
- ✅ Concurrency (multiple entries processing)
- ✅ State transitions (processing → completed/error/fetch-error)
- ✅ Properties drawer integrity (no orphaned drawers)
- ✅ Backward compatibility

### Test Maintenance

**When to update tests:**
- After fixing a bug (add regression test)
- When changing behavior (update assertions)
- When adding features (add integration test)
- When refactoring (ensure tests still pass)

**When to remove tests:**
- Never! Tests document behavior and prevent regressions.
- If behavior changes, update the test instead of removing it.

### Getting Help

- Check test output logs: `test-results-*.log`
- Review test fixtures: `test-fixtures/README.md`
- Look at test helpers: `org-capture-ai-test-helpers.el`
- See working examples: `org-capture-ai-regression-test.el`
