# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This repository contains **org-capture-ai**, a complete Emacs library for AI-enhanced URL capture in org-mode. It also includes the original comprehensive guide document that describes the implementation patterns.

### Files

- `org-capture-ai.el` - Main library implementing async URL capture with LLM processing
- `org-capture-ai-test.el` - ERT test suite
- `README.md` - User documentation and installation guide
- `examples/init-example.el` - Example configurations
- `compass_artifact_wf-cde1f498-4f12-4f9e-ab11-d78f7be83f24_text_markdown.md` - Original technical guide

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

Run tests with:
```elisp
(load-file "org-capture-ai-test.el")
(org-capture-ai-run-tests)
```

Or via ERT:
```elisp
M-x ert RET org-capture-ai-test- TAB
```

### Test Coverage

- HTML parsing and metadata extraction
- Readability-style content filtering
- Status property management
- Mock LLM responses (no API calls in tests)
- Setup/teardown lifecycle

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
(org-entry-put nil "CREATOR" author-name)
```
Follow [Dublin Core Element Set](https://www.dublincore.org/specifications/dublin-core/dces/) naming: TITLE, CREATOR, SUBJECT, DESCRIPTION, PUBLISHER, DATE, TYPE, FORMAT, IDENTIFIER, LANGUAGE, RIGHTS, SOURCE, RELATION, COVERAGE

2. **AI-generated properties** in `org-capture-ai--llm-analyze`:
```elisp
(org-entry-put nil "AI_MODEL" (symbol-name gptel-model))
```
Follow naming convention: `AI_*` for LLM-generated, uppercase with underscores.

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

## Git Configuration

- Default branch: `main`
- This is a local repository with no configured remote
