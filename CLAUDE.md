# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This repository contains **org-capture-ai**, a complete Emacs library for AI-enhanced URL capture in org-mode. It also includes the original comprehensive guide document that describes the implementation patterns.

### Files

- `org-capture-ai.el` - Main library implementing async URL capture with LLM processing
- `org-capture-ai-test.el` - ERT test suite
- `README.md` - User documentation and installation guide
- `examples/init-example.el` - Example configurations
- `org-capture-ai-implementation-guide.md` - Original technical implementation guide
- `LLM-INTEGRATION.md` - Detailed documentation of LLM interaction and prompt engineering
- `guide-bookmark-classification.md` - Comprehensive guide to bookmark classification systems

## Architecture

### Core Workflow

```
Capture → Finalize → Fetch URL → Extract Content → Call LLM → Update Properties
```

All processing is asynchronous to avoid blocking Emacs UI.

### Key Components

1. **HTML Processing Layer** (`org-capture-ai-fetch-url`, `org-capture-ai-extract-metadata`, `org-capture-ai-extract-readable-content`)
   - Async URL retrieval using `url-retrieve`
   - HTML parsing with `libxml-parse-html-region`
   - Dublin Core metadata extraction (ISO 15836 standard)
   - Readability-style content extraction (removes ads, navigation, scripts)

2. **LLM Integration Layer** (`org-capture-ai-llm-*`)
   - Wraps `gptel-request` for non-interactive LLM queries
   - Generates summaries and extracts tags
   - Retry logic for failed requests

3. **Capture Integration** (`org-capture-ai--process-entry`, `org-capture-ai--async-process`)
   - Hooks into `org-capture-after-finalize-hook`
   - Uses `org-capture-last-stored` bookmark to locate captured entry
   - Marker-based async updates to org properties

4. **Queue & Batch Processing** (`org-capture-ai-process-queued`)
   - Optional queuing for idle-time processing
   - Manual reprocessing command
   - Idle timer for automatic batch processing

### State Machine

Entries progress through STATUS property values:
- `processing` → `fetching` → `processing` → `completed`
- Error states: `fetch-error`, `error` (with ERROR property)
- Queue state: `queued` (for batch processing)

### Marker Pattern for Async Updates

```elisp
;; Create marker
(let ((marker (point-marker)))
  ;; Later in async callback:
  (save-excursion
    (org-with-point-at marker
      (org-entry-put nil "PROPERTY" "value")))
  ;; Clean up
  (set-marker marker nil))
```

## Testing

### Quick Start

Run all tests:
```bash
./run-tests.sh
```

Run specific test suite:
```bash
./run-tests.sh regression    # Regression tests (most important)
./run-tests.sh error         # Error condition tests
./run-tests.sh integration   # Integration tests
```

### Test Infrastructure

The test suite is organized into multiple specialized files:

1. **`org-capture-ai-test-helpers.el`** - Shared utilities
   - Fixture loading system
   - Assertion helpers (properties, drawer structure, orphaned drawers)
   - Mock helpers for LLM and URL fetching
   - Test environment setup/teardown
   - Entry creation and async waiting utilities

2. **`org-capture-ai-regression-test.el`** - Tests for specific bugs
   - Each test documents: bug description, root cause, fix, date, file/line
   - **Most critical tests** - These verify bugs stay fixed
   - Run with: `./run-tests.sh regression`

3. **`org-capture-ai-error-test.el`** - Error condition tests
   - Network failures, empty content, LLM errors
   - Edge cases: special characters, long values, concurrent processing

4. **`org-capture-ai-integration-test-v2.el`** - End-to-end tests
   - Complete workflow with mocked dependencies
   - Fixture-based testing
   - Performance benchmarks

5. **`test-fixtures/`** - Test data
   - `html/` - HTML pages for various scenarios
   - `llm-responses/` - Mock LLM responses
   - `snapshots/` - Expected outputs

### Test-Driven Development Workflow

**When fixing a bug or adding a feature:**

1. **Write failing test first**
   ```bash
   # Add test to org-capture-ai-regression-test.el
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

### Adding a Regression Test

When you encounter a bug:

```elisp
(ert-deftest org-capture-ai-regression-YYYYMMDD-brief-name ()
  "Regression: Brief description of bug.

Bug: Detailed description of what went wrong.

Root cause: Why it happened.

Fix: What was changed to fix it.

Date: YYYY-MM-DD
File: filename.el lines XX-YY"
  (org-capture-ai-test--with-mocked-env
   ;; Minimal reproduction case
   (setq org-capture-ai-test--mock-html-response
         (org-capture-ai-test--load-fixture "html" "your-fixture.html"))

   (with-current-buffer (find-file-noselect org-capture-ai-test--temp-file)
     (let* ((marker (org-capture-ai-test--create-processing-entry
                     "https://example.com/test"))
            (entry-pos (marker-position marker)))

       (org-capture-ai--async-process marker)
       (org-capture-ai-test--wait-for-processing marker)

       ;; Navigate back to entry (marker gets invalidated)
       (goto-char entry-pos)
       (org-back-to-heading t)

       ;; Assertions that verify the bug is fixed
       (should (= 1 (org-capture-ai-test--count-properties-drawers)))
       (should (equal "completed" (org-entry-get nil "STATUS")))))))
```

### Test Utilities Reference

**Assertions:**
```elisp
(org-capture-ai-test--assert-properties '(("STATUS" . "completed")))
(org-capture-ai-test--assert-single-properties-drawer)
(org-capture-ai-test--assert-no-orphaned-drawers (current-buffer))
(org-capture-ai-test--count-properties-drawers)
```

**Fixtures:**
```elisp
(org-capture-ai-test--load-fixture "html" "multiline-description.html")
(org-capture-ai-test--load-fixture "llm-responses" "normal-summary.txt")
```

**Test Flow:**
```elisp
(let* ((marker (org-capture-ai-test--create-processing-entry url))
       (entry-pos (marker-position marker)))  ; Save position before processing
  (org-capture-ai--async-process marker)
  (org-capture-ai-test--wait-for-processing marker)
  (goto-char entry-pos)  ; Navigate back after marker invalidated
  (org-back-to-heading t))
```

### Important Testing Notes

1. **Markers get invalidated** - `org-capture-ai--async-process` cleans up markers at the end. Save position with `(marker-position marker)` before processing, then use `(goto-char entry-pos)` to navigate back.

2. **No real API calls** - Tests use mocked `gptel-request` and `org-capture-ai-fetch-url` so they run fast and don't require API keys.

3. **Fixtures for consistency** - Use HTML fixtures in `test-fixtures/html/` for reproducible test cases.

4. **Document bugs** - Regression tests should explain the bug, root cause, and fix for future reference.

For complete documentation, see **`TESTING.md`**.

## Common Development Tasks

### Adding a New LLM Feature

1. Add function to LLM Integration Layer (prefix: `org-capture-ai-llm-`)
2. Wrap `gptel-request` with proper error handling
3. Add to processing pipeline in `org-capture-ai--llm-analyze`
4. Write test with mocked `gptel-request`

### Modifying Content Extraction

Edit `org-capture-ai-extract-readable-content`:
- Uses `dom-by-tag`, `dom-by-class` for element selection
- `dom-remove-node` to filter noise
- `dom-texts` to extract text content

### Adding Custom Properties

Properties are set in two places:

1. **Dublin Core metadata** in `org-capture-ai--process-html`:
```elisp
(org-entry-put nil "CREATOR" (org-capture-ai--sanitize-property-value author-name))
```
Follow [Dublin Core Element Set](https://www.dublincore.org/specifications/dublin-core/dces/) naming: TITLE, CREATOR, SUBJECT, DESCRIPTION, PUBLISHER, DATE, TYPE, FORMAT, IDENTIFIER, LANGUAGE, RIGHTS, SOURCE, RELATION, COVERAGE

2. **AI-generated properties** in `org-capture-ai--llm-analyze`:
```elisp
(org-entry-put nil "AI_MODEL" (org-capture-ai--sanitize-property-value (symbol-name gptel-model)))
```
Follow naming convention: `AI_*` for LLM-generated, uppercase with underscores.

**CRITICAL: Always sanitize property values** using `org-capture-ai--sanitize-property-value` before calling `org-entry-put`. This function:
- Replaces newlines with spaces (org properties must be single-line)
- Collapses multiple spaces
- Trims whitespace
- Truncates to 500 chars max

Multi-line property values will break the properties drawer and create orphaned `:PROPERTIES:` blocks. See regression test `org-capture-ai-regression-20251027-multiline-description` for details.

## Dependencies

- Emacs 27.1+ (for `cl-lib`, modern `org-mode`)
- org-mode 9.5+ (for reliable property handling)
- gptel 0.7.0+ (for LLM integration)
- Built-in: `url`, `dom`, `libxml`

## Configuration Pattern

Users configure via:
1. `defcustom` variables (all prefixed `org-capture-ai-`)
2. Call `(org-capture-ai-setup)` to install hooks and templates
3. gptel must be configured separately (API keys, models, backends)

## Known Issues & Fixes

### Fixed Issues (2025-10-27)

These bugs have been fixed and have regression tests to prevent recurrence:

1. **Multi-line property values breaking properties drawer**
   - **Symptom**: Orphaned `:PROPERTIES:` blocks appearing without headings
   - **Root cause**: HTML meta descriptions with newlines inserted directly into properties
   - **Fix**: `org-capture-ai--sanitize-property-value` function (lines 688-703)
   - **Test**: `org-capture-ai-regression-20251027-multiline-description`

2. **Hook duplication causing double processing**
   - **Symptom**: Entries processed multiple times, duplicate drawers
   - **Root cause**: Calling `org-capture-ai-setup` multiple times added hook multiple times
   - **Fix**: Made setup idempotent by removing hook before adding (lines 932-933)
   - **Test**: `org-capture-ai-regression-20251027-duplicate-processing`

3. **Heading replacement destroying structure**
   - **Symptom**: Tags lost when heading updated, drawer structure broken
   - **Root cause**: Used `replace-match` which destroys heading line
   - **Fix**: Use `org-edit-headline` API which preserves tags (line 785)
   - **Test**: `org-capture-ai-regression-20251027-heading-replacement`

All three bugs are covered by regression tests in `org-capture-ai-regression-test.el`. Run `./run-tests.sh regression` to verify they stay fixed.

## Git Configuration

- Default branch: `main`
- This is a local repository with no configured remote
