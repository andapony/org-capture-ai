# org-capture-ai

AI-enhanced URL capture for Emacs org-mode using LLMs. Automatically fetch web content, generate summaries, and extract tags using AI models via [gptel](https://github.com/karthink/gptel).

## Features

- **Async Processing**: Non-blocking workflow that keeps Emacs responsive
- **Smart Content Extraction**: Automatically removes ads, navigation, and other noise from web pages
- **Dublin Core Metadata**: Extracts standardized metadata (ISO 15836) from web pages
- **AI Summaries**: Generate concise summaries of captured web content
- **Automatic Tagging**: Extract relevant topic tags using LLMs
- **Batch Processing**: Queue entries for later processing during idle time
- **Retry Logic**: Automatically retry failed LLM requests
- **Status Tracking**: Property-based state machine tracks processing status
- **Flexible Configuration**: Customizable via Emacs customization system

## Workflow

```
Capture → Finalize → Fetch URL → Extract Content → Call LLM → Update Properties
```

All processing happens asynchronously after the capture is finalized.

## Requirements

- Emacs 27.1 or later
- org-mode 9.5 or later
- [gptel](https://github.com/karthink/gptel) 0.7.0 or later
- An LLM backend (OpenAI, Anthropic Claude, local Ollama, etc.)

## Installation

### Manual Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/example/org-capture-ai.git
   ```

2. Add to your Emacs init file:
   ```elisp
   (add-to-list 'load-path "/path/to/org-capture-ai")
   (require 'org-capture-ai)
   ```

### Using use-package

```elisp
(use-package org-capture-ai
  :load-path "/path/to/org-capture-ai"
  :after (org-capture gptel)
  :custom
  (org-capture-ai-default-file "~/Sync/org/bookmarks.org")
  (org-capture-ai-summary-sentences 3)
  (org-capture-ai-tag-count 5)
  :config
  (org-capture-ai-setup))
```

## Configuration

### Configure gptel First

org-capture-ai uses gptel for LLM integration. Configure your preferred backend:

```elisp
;; For OpenAI
(setq gptel-model 'gpt-4o
      gptel-api-key "your-api-key-here")

;; For Anthropic Claude
(setq gptel-backend (gptel-make-anthropic "Claude"
                      :stream t
                      :key "your-api-key-here")
      gptel-model 'claude-3-5-sonnet-20241022)

;; For local Ollama
(setq gptel-backend (gptel-make-ollama "Ollama"
                      :host "localhost:11434"
                      :stream t
                      :models '(llama3.1:latest)))
```

### Setup org-capture-ai

Call `org-capture-ai-setup` to initialize:

```elisp
(org-capture-ai-setup)
```

This will:
- Add a capture template with key "u" (customizable via `org-capture-ai-template-key`)
- Install the necessary hooks
- Start the batch processing timer (if configured)

### Customization Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `org-capture-ai-default-file` | `"~/Sync/org/bookmarks.org"` | Target file for captures |
| `org-capture-ai-template-key` | `"u"` | Capture template key |
| `org-capture-ai-summary-style` | `'sentences` | Summary format: `'sentences` (single) or `'paragraphs` (multi) |
| `org-capture-ai-summary-sentences` | `3` | Sentences in single-paragraph summaries (when style is `'sentences`) |
| `org-capture-ai-summary-overview-sentences` | `3` | Sentences in overview paragraph (when style is `'paragraphs`) |
| `org-capture-ai-summary-topic-paragraphs` | `'auto` | Number of topic paragraphs (`'auto` or integer) |
| `org-capture-ai-summary-topic-max-sentences` | `5` | Max sentences per topic paragraph |
| `org-capture-ai-use-curated-tags` | `t` | Use curated faceted tags instead of free-form |
| `org-capture-ai-tag-count` | `5` | Maximum tags (free-form mode only) |
| `org-capture-ai-tags-type` | see below | Curated tags for content type/format |
| `org-capture-ai-tags-status` | see below | Curated tags for status/lifecycle |
| `org-capture-ai-tags-quality` | see below | Curated tags for quality/authority |
| `org-capture-ai-tags-domain` | see below | Curated tags for domain/subject (customizable) |
| `org-capture-ai-max-retries` | `3` | Retry attempts for failed LLM requests |
| `org-capture-ai-enable-logging` | `t` | Enable logging to `*org-capture-ai-log*` |
| `org-capture-ai-batch-idle-time` | `300` | Seconds before processing queued entries (nil to disable) |
| `org-capture-ai-process-on-capture` | `t` | Process immediately (nil to queue for later) |

### Faceted Tagging System

org-capture-ai uses a **curated faceted tagging system** by default, based on research showing that action-oriented, multi-dimensional tags outperform free-form topic tags for long-term retrieval.

**Facet 1: Type (Content Format)**
- `article`, `tutorial`, `video`, `tool`, `reference`, `book`, `paper`, `course`
- LLM selects 1 tag describing the content format

**Facet 2: Status (Lifecycle/Action)**
- `to_read`, `active`, `reference`, `implemented`, `archived`
- LLM selects 1 tag indicating the current status (default: `to_read`)

**Facet 3: Quality (Authority Level)**
- `canonical`, `authoritative`, `exploratory`, `opinion`
- LLM optionally selects 1 tag for notably authoritative content

**Facet 4: Domain (Subject)**
- Default: `programming`, `data_science`, `machine_learning`, `web_development`, `security`, `productivity`, `design`, `business`, `research`, `writing`, `health`, `finance`
- LLM selects 1-3 tags matching the subject matter
- **Customize this list** to match your personal interests

Example bookmark tags: `article, to_read, canonical, programming, machine_learning`

This faceted approach enables powerful queries like:
- "Show me all tutorials I haven't read yet"
- "Find canonical reference materials about programming"
- "What active resources do I have for machine_learning?"

**Customizing Domain Tags:**
```elisp
(setq org-capture-ai-tags-domain
      '("emacs" "lisp" "org-mode" "ai" "nlp" "deep-learning"
        "functional-programming" "databases" "devops"))
```

**Switching to Free-Form Tags:**
```elisp
(setq org-capture-ai-use-curated-tags nil
      org-capture-ai-tag-count 5)
```

### Summary Formats

**Single paragraph (default):** `org-capture-ai-summary-style` = `'sentences`
- One paragraph with N sentences (configured by `org-capture-ai-summary-sentences`)
- Default: 3 sentences
- Clean, concise summary of the entire article

**Multi-paragraph (optional):** `org-capture-ai-summary-style` = `'paragraphs`
- First paragraph: Overview summarizing the entire article (3 sentences by default)
- Following paragraphs: One per major topic (up to 5 sentences each)
- LLM automatically determines number of topics (or specify with `org-capture-ai-summary-topic-paragraphs`)

Example configuration for multi-paragraph summaries:
```elisp
(setq org-capture-ai-summary-style 'paragraphs
      org-capture-ai-summary-overview-sentences 3
      org-capture-ai-summary-topic-max-sentences 5
      org-capture-ai-summary-topic-paragraphs 'auto)  ; or a number like 3
```

## Usage

### Basic Capture

1. Press `C-c c u` (or your configured org-capture key + "u")
2. Enter the URL
3. The capture automatically finalizes and begins processing

The entry will be automatically processed:
- URL fetched
- Content extracted
- Summary generated
- Tags extracted
- Properties updated
- File auto-saved when complete

### Resulting Org Entry

```org
* Example Article Title
:PROPERTIES:
:URL: https://example.com/article
:CAPTURED: [2025-10-04 Sat 14:30]
:STATUS: completed
:UPDATED_AT: [2025-10-04 Sat 14:32]
:PROCESSED_AT: [2025-10-04 Sat 14:32]
:TITLE: The Real Article Title from HTML
:CREATOR: John Doe
:PUBLISHER: example.com
:DATE: 2025-10-01
:TYPE: Text
:LANGUAGE: en
:FORMAT: text/html
:DESCRIPTION: A brief description from the page's meta tags
:SUBJECT: emacs, org-mode, llm, async-programming
:AI_MODEL: claude-sonnet-4-5-20250929
:END:

This article discusses the importance of async processing in Emacs. It provides
practical examples of using gptel for LLM integration. The author demonstrates
production-ready patterns for org-mode workflows.
```

### Dublin Core Properties

org-capture-ai extracts metadata following the [Dublin Core Metadata Element Set](https://www.dublincore.org/specifications/dublin-core/dces/) (ISO 15836):

| Property | Dublin Core Element | Description |
|----------|-------------------|-------------|
| `TITLE` | dc:title | Page title from HTML or meta tags |
| `CREATOR` | dc:creator | Author name (from meta tags, byline, or schema.org) |
| `SUBJECT` | dc:subject | AI-extracted topic keywords |
| `DESCRIPTION` | dc:description | Meta description from page |
| `PUBLISHER` | dc:publisher | Domain name or site name |
| `DATE` | dc:date | Publication date (from meta tags or article) |
| `TYPE` | dc:type | Resource type (usually "Text") |
| `FORMAT` | dc:format | Media type (text/html, application/pdf) |
| `IDENTIFIER` | dc:identifier | URL (stored in URL property) |
| `LANGUAGE` | dc:language | Language code (from `<html lang>` attribute) |
| `RIGHTS` | dc:rights | Copyright/license information |
| `SOURCE` | dc:source | Original source if content is derived/reposted |
| `RELATION` | dc:relation | Related resources |
| `COVERAGE` | dc:coverage | Spatial or temporal coverage |

Properties are only set when metadata is available in the source HTML.

### Status Values

Entries progress through these states:

- `processing` - Initial state after capture
- `fetching` - Downloading URL content
- `processing` - Calling LLM for analysis
- `completed` - Successfully processed
- `queued` - Waiting for batch processing
- `reprocessing` - Manually reprocessing entry
- `refreshing` - Refreshing entry (replacing content)
- `error` - Processing failed (check ERROR property)
- `fetch-error` - Failed to fetch URL

### Manual Reprocessing

**Reprocess (add to existing content):**

To reprocess a failed entry or add new AI analysis without removing existing content:

1. Navigate to the entry
2. Run `M-x org-capture-ai-reprocess-entry`

This will fetch the URL again and add new AI analysis, but won't remove your existing notes or content.

**Refresh (replace all content):**

To completely refresh an entry with updated content from the URL:

1. Navigate to the entry
2. Run `M-x org-capture-ai-refresh-entry`
3. Confirm the refresh when prompted

This will:
- Clear the existing summary and body content
- Clear all metadata properties and tags
- Re-fetch the URL
- Extract fresh metadata
- Generate a new AI summary and tags
- Replace the heading title

Use this when:
- The web page has been significantly updated
- You want to remove old/incorrect information
- You need a fresh analysis with current LLM capabilities

### Batch Processing

Process all queued entries:

```elisp
M-x org-capture-ai-process-queued
```

Or set `org-capture-ai-process-on-capture` to `nil` to queue all captures and process them during idle time.

## Testing

Run the test suite:

```elisp
(load-file "org-capture-ai-test.el")
(org-capture-ai-run-tests)
```

Or run individual tests:

```elisp
M-x ert RET org-capture-ai-test- TAB
```

## Architecture

### Async Processing Pipeline

```
org-capture-after-finalize-hook
  → org-capture-ai--process-entry
    → org-capture-ai--async-process
      → org-capture-ai-fetch-url (async)
        → org-capture-ai--process-html
          → org-capture-ai-extract-readable-content
          → org-capture-ai--llm-analyze
            → org-capture-ai-llm-summarize (async)
            → org-capture-ai-llm-extract-tags (async)
              → Update properties via markers
```

### Key Design Patterns

- **Marker-based updates**: Markers track buffer positions across async operations
- **Callback composition**: Async operations chain via callbacks
- **Status tracking**: Properties track processing state for debugging and recovery
- **Non-blocking**: All network and LLM operations are asynchronous

## Troubleshooting

### Enable Debug Logging

```elisp
(setq org-capture-ai-enable-logging t)
```

View logs in the `*org-capture-ai-log*` buffer.

### Common Issues

**Entry shows STATUS=fetch-error**
- Check the URL is accessible
- Check your network connection
- Look at the ERROR property for details

**Entry shows STATUS=error**
- Check gptel configuration
- Verify API key is valid
- Check `*org-capture-ai-log*` buffer
- Try reprocessing: `M-x org-capture-ai-reprocess-entry`

**No capture template appears**
- Verify `org-capture-ai-setup` was called
- Check `org-capture-templates` for the entry
- Ensure the template key doesn't conflict

### Disabling

To disable org-capture-ai:

```elisp
(org-capture-ai-teardown)
```

## Advanced Usage

### Custom Template

Instead of using the default template, create your own:

```elisp
(add-to-list 'org-capture-templates
             '("w" "Web Article with AI" entry
               (file "~/org/articles.org")
               "* %^{Title}
:PROPERTIES:
:URL: %^{URL}
:CAPTURED: %U
:STATUS: processing
:SOURCE: %^{Source|Blog|Paper|News}
:END:

%?"
               :empty-lines 1
               :after-finalize org-capture-ai--process-entry))
```

### Integration with org-protocol

Capture from your browser using org-protocol:

```elisp
(require 'org-protocol)

(defun my/org-protocol-capture-ai (info)
  "Capture web page with AI processing via org-protocol."
  (let* ((url (plist-get info :url))
         (title (plist-get info :title)))
    (org-capture-string
     (format "* %s\n:PROPERTIES:\n:URL: %s\n:CAPTURED: %s\n:STATUS: processing\n:END:\n"
             title url (format-time-string "[%Y-%m-%d %a %H:%M]"))
     "u")))

;; Bookmarklet:
;; javascript:location.href='org-protocol://capture-ai?url='+encodeURIComponent(location.href)+'&title='+encodeURIComponent(document.title)
```

### Multi-stage Processing

Extend the LLM analysis with custom processing:

```elisp
(defun my/custom-llm-analysis (text marker)
  "Custom multi-stage LLM analysis."
  (org-capture-ai-llm-summarize text
    (lambda (summary)
      (save-excursion
        (org-with-point-at marker
          (org-entry-put nil "AI_SUMMARY" summary)))

      ;; Additional processing: extract key questions
      (org-capture-ai-llm-request text
        "Generate 3 thought-provoking questions about this content."
        (lambda (questions info)
          (when questions
            (save-excursion
              (org-with-point-at marker
                (org-entry-put nil "AI_QUESTIONS" questions)))))))))
```

## Related Projects

- [gptel](https://github.com/karthink/gptel) - LLM client for Emacs
- [org-ai](https://github.com/rksm/org-ai) - AI assistance within org-mode
- [org-roam](https://github.com/org-roam/org-roam) - Note-taking workflow

## Contributing

Contributions are welcome! Please:

1. Run tests before submitting PRs
2. Follow existing code style
3. Add tests for new features
4. Update documentation

## License

GPLv3 or later

## Acknowledgments

Based on patterns described in [Building an Org-Mode URL Capture System with LLM-Based Tagging and Summarization](compass_artifact_wf-cde1f498-4f12-4f9e-ab11-d78f7be83f24_text_markdown.md).

Built on the excellent [gptel](https://github.com/karthink/gptel) library by Karthik Chikmagalur.
