# LLM Integration Guide

This document describes how org-capture-ai interacts with Large Language Models (LLMs) to generate summaries and extract tags from web content.

## Architecture Overview

### Request Flow

```
Web Content → Readability Filter → Text Extraction → LLM Processing → Property Updates
                                                     ↓
                                            (1) Summarization
                                            (2) Tag Extraction
                                            (3) Takeaway Extraction (if enabled)
```

The LLM interaction happens in three sequential phases:
1. **Summarization** - Generates title and summary; first sentence becomes DESCRIPTION
2. **Tag Extraction** - Extracts relevant tags into the SUBJECT property (triggered by summarization callback)
3. **Takeaway Extraction** - Extracts 3-5 key insights into TAKEAWAYS (if `org-capture-ai-extract-takeaways` is non-nil)

This sequential approach ensures properties are set in the correct order and allows each phase to potentially leverage the previous result.

## Core Integration Layer

### `org-capture-ai-llm-request`

The foundation function that wraps `gptel-request` with error handling:

```elisp
(defun org-capture-ai-llm-request (prompt system-msg callback)
  "Make LLM request with PROMPT and SYSTEM-MSG.
Call CALLBACK with (response info) on completion."
```

**Key design decisions:**

1. **UTF-8 encoding** - Uses temporary buffer with explicit `utf-8` encoding to handle international content
2. **Non-streaming** - Sets `:stream nil` for predictable, complete responses
3. **Error wrapping** - Catches errors and converts to callback format
4. **Logging** - Comprehensive logging at every step for debugging

**Why non-streaming?**
- Streaming is excellent for interactive use (showing progress)
- For automated processing, we need the complete response to parse structured output
- Simplifies parsing of `TITLE:` and `SUMMARY:` format

## Prompt Engineering

### Principles

All prompts follow these principles:

1. **Explicit format specification** - Exact format with examples
2. **Constraint statements** - "IMPORTANT:" sections with requirements
3. **Quality guidelines** - Complete sentences, proper punctuation, no truncation
4. **Minimal free-form** - Structured output over natural language
5. **Self-contained** - Each prompt includes all context needed

### Summarization Prompt

#### Single-Paragraph Format (default)

```
Generate a title and summary for this content.

Return your response in this exact format:
TITLE: [A concise, descriptive title in 3-8 words]
SUMMARY: [A N-sentence summary focusing on the main thesis and key insights]

IMPORTANT: The first sentence of the SUMMARY must be a complete,
grammatically correct sentence that stands alone as a clear description
of the content. Ensure proper punctuation and no truncation.

Do not include any other text or formatting.
```

**Design rationale:**

- **"exact format"** - Signals to LLM this is not creative writing
- **Word/sentence counts** - Provides concrete constraints
- **"first sentence" emphasis** - Critical because this becomes the DESCRIPTION property
- **"Do not include..."** - Prevents LLM from adding meta-commentary

**Why this matters:**
The DESCRIPTION property often appears in search results, link previews, and org-mode sparse trees. A truncated or malformed description degrades the entire system.

#### Multi-Paragraph Format (optional)

For longer articles, users can enable `org-capture-ai-summary-style` set to `'paragraphs`:

```
Generate a title and multi-paragraph summary for this content.

Return your response in this exact format:
TITLE: [A concise, descriptive title in 3-8 words]
SUMMARY:
[First paragraph: N-sentence overview summarizing the entire article]

[Second paragraph: Summary of first major topic, up to M sentences]

[Third paragraph: Summary of second major topic, up to M sentences]

IMPORTANT:
- Each paragraph should be on its own line, separated by blank lines
- First paragraph must be exactly N sentences summarizing the whole article
- The FIRST SENTENCE of the first paragraph must be a complete, grammatically
  correct sentence that stands alone as a clear, concise description
- Following paragraphs cover major topics, each up to M sentences
- Write naturally - each paragraph should flow well and be readable
- Ensure proper punctuation and no truncation in all sentences
```

**Design rationale:**

- **Explicit blank lines** - Ensures proper org-mode formatting
- **Numbered paragraph structure** - Helps LLM maintain organization
- **"Write naturally"** - Counterbalances the structural constraints
- **Repeated first-sentence emphasis** - Critical for DESCRIPTION property

**Configurability:**

Users control:
- `org-capture-ai-summary-sentences` (default: 3)
- `org-capture-ai-summary-overview-sentences` (default: 3)
- `org-capture-ai-summary-topic-max-sentences` (default: 5)
- `org-capture-ai-summary-topic-paragraphs` (default: `'auto`)

### Tag Extraction Prompt

#### Curated Faceted Tags (default)

```
Analyze this content and select appropriate tags from these faceted lists:

TYPE (choose 1-2):
article, video, tutorial, tool, reference, paper, book, course, documentation

DOMAIN (choose 2-4):
programming, design, research, writing, productivity, science, business,
technology, education, health, finance, art, music, philosophy, history,
politics, culture

STATUS (choose 1):
to_read, reference, archive, inspiration, cite

QUALITY (choose 0-1):
authoritative, canonical, exploratory

Select the most relevant tags that accurately describe the content.
Return ONLY the selected tags as a comma-separated list.
Do not include explanations or categories.

Example: article, programming, reference, authoritative
```

**Design rationale:**

- **Faceted structure** - Ensures tags span multiple dimensions
- **Explicit counts** - "choose 1-2" guides tag density
- **Concrete options** - LLM chooses from list rather than generating
- **Example format** - Shows exact output format
- **"Do not include..."** - Prevents category labels in output

**Benefits:**
- **Consistent vocabulary** - Tags are predictable and searchable
- **Multi-dimensional** - Captures format, subject, status, and quality
- **Appropriate density** - 4-7 tags typically, avoiding over/under-tagging

**Configurability:**

Users can customize the tag lists:
- `org-capture-ai-tags-type`
- `org-capture-ai-tags-domain`
- `org-capture-ai-tags-status`
- `org-capture-ai-tags-quality`

#### Free-Form Tags (optional)

When `org-capture-ai-use-curated-tags` is `nil`:

```
Analyze this content and extract N relevant topic tags.

Return ONLY comma-separated tags (e.g., 'machine_learning, python, tutorial').
Use underscores instead of hyphens for multi-word tags.
No explanation, no extra formatting, no categories.

Guidelines:
- Use lowercase with underscores for multi-word tags
- Focus on concrete topics, technologies, and concepts
- Avoid vague tags like "interesting" or "good"
- Include both broad topics and specific details
```

**Design rationale:**

- **Example format** - Shows underscore style for org-mode compatibility
- **"ONLY comma-separated"** - Emphasizes simplicity
- **Anti-patterns** - Explicitly discourages vague tags
- **Balance guidance** - "broad topics and specific details"

**Trade-offs:**
- **Pros**: Captures specific topics not in curated lists
- **Cons**: Can generate inconsistent vocabulary, synonyms, spelling variants

### Takeaway Extraction Prompt

When `org-capture-ai-extract-takeaways` is non-nil (the default):

```
Extract 3-5 key takeaways from this content.
Each takeaway must be a single, self-contained sentence capturing one important insight.
Return ONLY a numbered list, one takeaway per line, no extra text.
```

**Design rationale:**

- **Numbered list format** - Easy to parse line-by-line with regex
- **"self-contained sentence"** - Each takeaway must stand alone for search/display
- **3-5 range** - Enough for depth without overwhelming

**Output:** Stored in the `TAKEAWAYS` property as pipe-separated sentences:
```
First insight here. | Second insight here. | Third insight here.
```

**Disabling takeaways:**
```elisp
(setq org-capture-ai-extract-takeaways nil)
```

### Response Parsing

#### Summarization Response

Expected format:
```
TITLE: Actual Title Here
SUMMARY: First sentence complete. Second sentence here. Third sentence here.
```

Parsing regex:
```elisp
"TITLE:\\s-*\\(.*?\\)\\s-*\nSUMMARY:\\s-*\\([^\000]*\\)"
```

**Robustness considerations:**

1. **Flexible whitespace** - `\\s-*` handles varying spaces/tabs
2. **Greedy summary capture** - `[^\000]*` captures everything after SUMMARY:
3. **Fallback handling** - If parsing fails, uses full response as summary
4. **Trim whitespace** - `string-trim` on extracted components

**Edge cases handled:**
- LLM adds extra newlines → regex handles it
- TITLE includes punctuation → captured as-is
- SUMMARY is multi-paragraph → entire block captured

#### Tag Response

Expected format:
```
article, programming, reference, authoritative
```

Parsing:
```elisp
(split-string (string-trim response) "," t)
```

**Robustness considerations:**

1. **Split on comma** - Standard delimiter
2. **Trim each tag** - Handles "tag1, tag2" vs "tag1,tag2"
3. **Remove empty** - `t` parameter eliminates empty strings

**Post-processing:**
```elisp
(mapcar #'string-trim tags)  ; Remove whitespace from each tag
```

## Content Preprocessing

### Text Extraction Strategy

Before sending to LLM, web content goes through readability filtering:

```elisp
(defun org-capture-ai-extract-readable-content (html)
  "Extract main readable content from HTML, filtering noise.")
```

**Removal targets:**

1. **Structural noise**: `<script>`, `<style>`, `<nav>`, `<header>`, `<footer>`, `<aside>`
2. **Advertisement classes**: `.advertisement`, `.ads`, `.sidebar`
3. **Interactive noise**: `.comment`, `.comments`

**Content extraction priority:**

1. `<article>` tag (semantic HTML5)
2. `<main>` tag (semantic HTML5)
3. `<body>` tag (fallback)

**Why this matters:**

- **Token efficiency** - Reduces input length by 50-80%
- **Noise reduction** - Removes ads, navigation, unrelated content
- **Cost savings** - Fewer tokens = lower API costs
- **Better results** - LLM focuses on actual content

### Token Considerations

**Typical token counts:**

- Short article (500 words): ~700 tokens
- Medium article (1500 words): ~2100 tokens
- Long article (3000 words): ~4200 tokens

**Current approach:**

No truncation - sends full extracted content to LLM. This assumes:
- Readability filtering reduces content significantly
- Most articles fit within model context windows (200K+ tokens for Claude Sonnet)
- Full context produces better summaries

**Future considerations:**

For very long content (10K+ words), could implement:
- Chunking with summary aggregation
- Head + tail extraction
- Configurable max token limit

## Error Handling

### Three-Layer Error Handling

1. **Network/HTTP errors** - Caught in `url-retrieve` callback
2. **LLM request errors** - Caught in `gptel-request` wrapper
3. **Parsing errors** - Caught in response processing

### Error Recovery Strategy

```elisp
(condition-case err
    (gptel-request prompt ...)
  (error
   (org-capture-ai--log "Error in gptel-request: %s" err)
   (funcall callback nil (list :status (format "error: %s" err)))))
```

**Callback pattern:**

All errors result in `(callback nil info)` where `info` contains `:status` with error description.

**Status property progression:**

- Success: `processing` → `fetching` → `processing` → `completed`
- Error: `processing` → `error` (with ERROR property)
- Network error: `processing` → `fetch-error`

### Retry Logic

**Current implementation:** Configurable retries via `org-capture-ai-max-retries` (default: 3).

When an LLM request returns a nil response (transient failure), the request is retried
up to `org-capture-ai-max-retries` times before recording an error.

**Rationale:**
- Transient failures (rate limits, timeouts) are retried automatically
- Permanent failures (bad API key, invalid model) are surfaced as errors
- Network failures at URL fetch layer are handled separately
- Users can always manually retry with `org-capture-ai-reprocess-entry`

## Property Management

### Metadata Flow

```
HTML → Dublin Core metadata → Org properties
                ↓
             (if corrupted)
                ↓
         LLM-generated description
```

**Key insight:** HTML metadata is untrusted due to:
- Encoding issues (mojibake, replacement characters)
- Truncation (incomplete meta descriptions)
- Spam/SEO gaming (keyword stuffing)

**Solution:** Always overwrite DESCRIPTION with AI-generated first sentence.

### Property Naming Conventions

**Dublin Core Standard** (ISO 15836):
- TITLE - Resource title
- CREATOR - Author/creator
- SUBJECT - Tags/keywords (comma-separated)
- DESCRIPTION - Brief description
- PUBLISHER - Publishing entity
- DATE - Publication date
- TYPE - Resource type
- FORMAT - MIME type
- IDENTIFIER - URL
- LANGUAGE - ISO language code

**AI-Generated Properties** (prefixed with AI_):
- AI_MODEL - Model identifier (e.g., `claude-sonnet-4-5-20250929`)
- AI_SUMMARY - (stored in body text, not property)
- AI_TAGS - (stored in SUBJECT property)

**Status Properties**:
- STATUS - Processing state (`processing`, `completed`, `error`, etc.)
- UPDATED_AT - Last update timestamp
- PROCESSED_AT - Completion timestamp
- ERROR - Error message (if STATUS is error)

## Quality Assurance

### Ensuring Clean Descriptions

**Problem:** HTML meta descriptions often have encoding corruption.

**Example of corruption:**
```
"I feel like vibe coding is pretty well established now as covering the fast,
loose and irresponsible way of building software with AIÁ¢ÀÀentirely prompt-driven..."
```

**Solution:** Three-layer approach:

1. **Filter at extraction** - Reject corrupted HTML meta descriptions:
```elisp
;; Check for Unicode replacement character and common mojibake patterns
(when (and (> (length cleaned) 10)
           (not (string-match-p "\uFFFD\\|�\\|Á¢À\\|â€\\|Ã¢â‚¬" cleaned)))
  cleaned)
```

2. **Emphasize in prompt** - "The first sentence must be complete and grammatically correct"

3. **Always overwrite** - Use AI-generated first sentence even if HTML meta exists

### Validation and Logging

**Comprehensive logging** (when `org-capture-ai-enable-logging` is `t`):

```
[2025-10-08 09:22] Fetching URL: https://example.com
[2025-10-08 09:22] HTTP status: 200
[2025-10-08 09:22] Extracted 2453 chars of text
[2025-10-08 09:22] LLM request: Generate a title... (prompt length: 2453 chars)
[2025-10-08 09:22] LLM response received (348 chars)
[2025-10-08 09:22] Calling tag extraction...
[2025-10-08 09:22] Processing complete
```

**Logged to:** `*org-capture-ai-log*` buffer

**User-facing messages:**
```
org-capture-ai: Fetching https://example.com
org-capture-ai: Processing complete
```

## Configuration Guide

### Minimal Configuration

```elisp
(setq org-capture-ai-summary-sentences 3)
(setq org-capture-ai-tag-count 5)
```

### Advanced Configuration

```elisp
;; Use multi-paragraph summaries
(setq org-capture-ai-summary-style 'paragraphs)
(setq org-capture-ai-summary-overview-sentences 3)
(setq org-capture-ai-summary-topic-max-sentences 4)
(setq org-capture-ai-summary-topic-paragraphs 'auto)

;; Use free-form tags instead of curated
(setq org-capture-ai-use-curated-tags nil)

;; Enable detailed logging
(setq org-capture-ai-enable-logging t)

;; Customize curated tag domain list
(setq org-capture-ai-tags-domain
      '("emacs" "lisp" "ai" "web_dev" "data_science"))

;; Disable takeaway extraction
(setq org-capture-ai-extract-takeaways nil)
```

## Best Practices

### Prompt Design

1. **Be explicit** - Specify exact format, not "generate a summary"
2. **Use examples** - Show desired output format
3. **Set constraints** - Word counts, sentence counts, specific requirements
4. **Prevent overfitting** - Balance structure with "write naturally"
5. **Anticipate failures** - Handle missing or malformed responses

### Token Management

1. **Preprocess content** - Remove noise before sending to LLM
2. **Monitor costs** - Log token usage for budgeting
3. **Consider truncation** - For very long articles
4. **Cache when possible** - Future enhancement

### Error Recovery

1. **Log everything** - Enable logging for debugging
2. **Surface errors** - Show clear messages to users
3. **Enable retry** - Manual reprocessing command
4. **Graceful degradation** - Partial results better than failure

### Testing Strategy

1. **Mock LLM responses** - Unit tests shouldn't call APIs
2. **Test parsing** - Verify regex handles edge cases
3. **Test corruption handling** - Ensure bad HTML doesn't break system
4. **Integration tests** - End-to-end with real URLs (development only)

## Future Enhancements

### Potential Improvements

1. **Adaptive summarization** - Adjust length based on content length
2. **Retry with backoff** - Automatic retry for transient failures
3. **Response caching** - Cache LLM responses by content hash
4. **Token budgeting** - Truncate very long content intelligently
5. **Quality scoring** - Ask LLM to rate confidence in summary
6. **Multi-language support** - Detect and handle non-English content
7. **Streaming summaries** - Show partial results as they arrive
8. **Batch processing** - Process multiple URLs in parallel

### Advanced Prompt Techniques

1. **Chain-of-thought** - Ask LLM to explain reasoning before answering
2. **Self-consistency** - Generate multiple summaries and aggregate
3. **Few-shot examples** - Include example articles and summaries
4. **Critique and refine** - Ask LLM to critique then improve its summary

## Troubleshooting

### Common Issues

**Issue: LLM returns malformed response**
- Check `*org-capture-ai-log*` for actual response
- Verify prompt is clear and unambiguous
- Check if model supports required output format

**Issue: Descriptions are truncated**
- Verify HTML meta description filtering is working
- Check if LLM prompt emphasizes complete sentences
- Enable logging to see raw LLM responses

**Issue: Tags are inconsistent**
- Switch to curated tags mode
- Review and customize curated tag lists
- Add post-processing to normalize tags

**Issue: Processing is slow**
- Check network latency to API
- Monitor token counts (very long articles)
- Consider local LLM (Ollama) for faster processing

## References

- [Dublin Core Metadata Element Set](https://www.dublincore.org/specifications/dublin-core/dces/)
- [gptel documentation](https://github.com/karthink/gptel)
- [Anthropic Claude API docs](https://docs.anthropic.com/claude/reference)
- [OpenAI API docs](https://platform.openai.com/docs)
