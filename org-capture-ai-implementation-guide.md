# Building an Org-Mode URL Capture System with LLM-Based Tagging and Summarization

**The capture-analyze-enrich workflow combines org-capture's flexibility with gptel's programmatic LLM API to automatically fetch, process, and annotate web content. This guide provides production-ready patterns for implementing async LLM processing within org-mode's capture infrastructure.**

Org-capture finalizes in seconds, but LLM calls take longer. The winning pattern is **capture immediately, process asynchronously** using hooks and bookmarks to update entries after finalization. This approach keeps the UI responsive while enabling sophisticated AI-powered enrichment of captured content.

## Core Architecture: The Async Processing Pipeline

The implementation follows this flow: **Capture → Finalize → Fetch URL → Call LLM → Update Properties**. Each stage runs asynchronously to avoid blocking Emacs, with the capture template creating a skeleton entry that gets enriched by background processing.

### Key Components Integration Map

**org-capture-templates** define the initial structure. **org-capture-after-finalize-hook** triggers async processing. **url-retrieve** fetches web content non-blocking. **gptel-request** processes content with Claude/GPT. **org-entry-put** updates properties with results. The bookmark `org-capture-last-stored` provides the anchor point for finding and updating the captured entry after async completion.

## Extending Org-Capture Templates with Custom Functions

### Template Target Functions

Capture templates accept functions as targets to dynamically determine where content goes:

```elisp
(defun my/find-capture-location ()
  "Find or create the appropriate capture location."
  (find-file "~/org/captures.org")
  (goto-char (point-max))
  (unless (bolp) (insert "\n")))

(setq org-capture-templates
      '(("u" "URL with AI" entry
         (function my/find-capture-location)
         "* %?
:PROPERTIES:
:URL: %:link
:CREATED: %U
:STATUS: processing
:END:
")))
```

### Dynamic Template Generation

Templates can be functions that return template strings, enabling conditional formatting:

```elisp
(defun my/ai-capture-template ()
  "Generate template with context-aware fields."
  (let ((timestamp (format-time-string "[%Y-%m-%d %a %H:%M]"))
        (backend (symbol-name gptel-backend)))
    (format "* %%^{Title}
:PROPERTIES:
:URL: %%:link
:CAPTURED: %s
:AI_BACKEND: %s
:STATUS: queued
:END:

%%:initial

** Original Content
%%?
" timestamp backend)))

(add-to-list 'org-capture-templates
             '("a" "AI-enhanced URL" entry
               (file+headline "~/org/bookmarks.org" "Bookmarks")
               (function my/ai-capture-template)))
```

### Accessing Template Context with org-capture-plist

Custom properties in templates flow through `org-capture-plist`:

```elisp
(defun my/template-with-context ()
  "Access custom template properties."
  (let ((model (plist-get org-capture-plist :ai-model))
        (prompt-type (plist-get org-capture-plist :prompt-style)))
    (format "* %s [Model: %s, Style: %s]\n%%?" 
            (read-string "Title: ") model prompt-type)))

(setq org-capture-templates
      '(("s" "Summarize with GPT-4" entry
         (file "~/notes.org")
         (function my/template-with-context)
         :ai-model "gpt-4o"
         :prompt-style "concise")))
```

## Hook Points in the Org-Capture Workflow

### The Four Primary Hooks

Org-capture provides strategically placed hooks for different processing stages:

**org-capture-mode-hook** runs when entering capture mode—buffer is narrowed, ideal for initial setup. **org-capture-prepare-finalize-hook** fires before finalization begins while buffer remains narrowed—perfect for last-minute content edits. **org-capture-before-finalize-hook** executes just before saving with buffer widened—use for property insertion and validation. **org-capture-after-finalize-hook** triggers after capture completes—the canonical place for async LLM processing.

### Execution Order and Usage

```elisp
;; 1. User initiates capture
;; 2. org-capture-mode-hook (buffer narrowed)
;; 3. [User edits content OR :immediate-finish t auto-finalizes]
;; 4. User presses C-c C-c (or auto-finalize with :immediate-finish t)
;; 5. org-capture-prepare-finalize-hook (still narrowed)
;; 6. org-capture-before-finalize-hook (now widened)
;; 7. Content saved to target
;; 8. org-capture-after-finalize-hook (back to original buffer)
```

### Template-Specific Hooks

Modern org-mode supports per-template hooks for cleaner isolation:

```elisp
(setq org-capture-templates
      '(("w" "Web article" entry
         (file "~/articles.org")
         "* %^{Title}
:PROPERTIES:
:URL: %^{URL}
:END:
"
         :prepare-finalize my/prepare-web-content
         :after-finalize my/process-with-llm)))
```

### Conditional Hook Execution

For shared hooks that act on specific templates:

```elisp
(defun my/template-specific-llm-processing ()
  "Process only URL capture templates."
  (when (and (not org-note-abort)
             (member (plist-get org-capture-plist :key) 
                     '("u" "w" "b")))  ; URL template keys
    (my/start-async-llm-processing)))

(add-hook 'org-capture-after-finalize-hook 
          #'my/template-specific-llm-processing)
```

## Using gptel-request for Non-Interactive LLM Queries

### Basic Programmatic API Call

**gptel-request** is the non-interactive workhorse for automated LLM queries:

```elisp
(gptel-request "Summarize this: Emacs is a text editor"
  :callback (lambda (response info)
              (if response
                  (message "Summary: %s" response)
                (message "Error: %s" (plist-get info :status)))))
```

### Complete Callback Pattern with Error Handling

The callback receives two arguments—response string (nil on failure) and info plist with metadata:

```elisp
(defun my/safe-gptel-request (prompt system-msg callback)
  "Make gptel request with comprehensive error handling."
  (gptel-request prompt
    :system system-msg
    :stream nil  ; Disable streaming for predictable results
    :callback
    (lambda (response info)
      (cond
       ((not response)
        (let ((error-status (plist-get info :status)))
          (message "LLM request failed: %s" error-status)
          (funcall callback nil (list :error error-status))))
       
       ((string-empty-p response)
        (message "Empty response from LLM")
        (funcall callback nil (list :error "empty-response")))
       
       (t
        (funcall callback response info))))))
```

### Configuring Backend and Model

Set up Claude or other backends programmatically:

```elisp
;; Configure Claude (Anthropic)
(setq gptel-backend (gptel-make-anthropic "Claude"
                      :stream t
                      :key (lambda () (auth-source-pick-first-password
                                      :host "api.anthropic.com"))))
(setq gptel-model 'claude-3-5-sonnet-20241022)

;; Or use GPT-4
(setq gptel-model 'gpt-4o
      gptel-api-key #'my-openai-key-function)

;; Or local Ollama
(setq gptel-backend (gptel-make-ollama "Ollama"
                      :host "localhost:11434"
                      :stream t
                      :models '(llama3.1:latest mistral:latest)))
```

### Specialized Requests for Tagging and Summarization

**Tagging extraction** with constrained output:

```elisp
(defun my/extract-tags (text callback)
  "Extract tags from TEXT using LLM."
  (gptel-request text
    :system "Extract 3-5 relevant topic tags from the text. 
Return ONLY comma-separated tags, no explanation or formatting."
    :callback
    (lambda (response info)
      (when response
        (let ((tags (split-string (string-trim response) "," t)))
          (funcall callback (mapcar #'string-trim tags)))))))
```

**Summarization** with length control:

```elisp
(defun my/summarize-content (text word-count callback)
  "Summarize TEXT in approximately WORD-COUNT words."
  (gptel-request text
    :system (format "Summarize the following content in approximately %d words. 
Focus on key points and main ideas. Be concise and clear."
                    word-count)
    :callback
    (lambda (response info)
      (if response
          (funcall callback response)
        (funcall callback 
                 (format "[Summarization failed: %s]" 
                        (plist-get info :status)))))))
```

### Context Management with Markers

Use markers to track buffer positions during async operations:

```elisp
(defun my/process-with-context (text entry-marker)
  "Process TEXT and update entry at ENTRY-MARKER."
  (gptel-request text
    :context (list :marker entry-marker
                   :timestamp (current-time))
    :callback
    (lambda (response info)
      (when response
        (let* ((context (plist-get info :context))
               (marker (plist-get context :marker))
               (start-time (plist-get context :timestamp)))
          (save-excursion
            (org-with-point-at marker
              (org-entry-put nil "AI_SUMMARY" response)
              (org-entry-put nil "PROCESSING_TIME"
                           (format "%.2f seconds"
                                 (float-time (time-since start-time))))))
          (set-marker marker nil))))))  ; Clean up marker
```

## Fetching URL Content Programmatically

### Asynchronous URL Retrieval

**url-retrieve** is the foundation for non-blocking fetches:

```elisp
(defun my/fetch-url-async (url success-callback error-callback)
  "Fetch URL asynchronously with proper error handling."
  (url-retrieve url
    (lambda (status)
      ;; Check for network errors
      (let ((error-info (plist-get status :error)))
        (if error-info
            (progn
              (kill-buffer)
              (funcall error-callback error-info))
          
          ;; Check HTTP status code
          (goto-char (point-min))
          (if (re-search-forward "^HTTP/[0-9.]+ \\([0-9]+\\)" nil t)
              (let ((status-code (string-to-number (match-string 1))))
                (if (and (>= status-code 200) (< status-code 300))
                    (progn
                      ;; Success - skip headers and extract body
                      (re-search-forward "^\r?\n\r?\n")
                      (let ((content (buffer-substring (point) (point-max))))
                        (kill-buffer)
                        (funcall success-callback content)))
                  ;; HTTP error
                  (kill-buffer)
                  (funcall error-callback 
                          (format "HTTP %d" status-code))))
            ;; Couldn't parse response
            (kill-buffer)
            (funcall error-callback "Invalid HTTP response")))))))
```

### Parsing HTML with libxml and dom.el

Extract structured content from HTML:

```elisp
(defun my/parse-html-extract-article (html-string)
  "Parse HTML and extract main article content."
  (with-temp-buffer
    (insert html-string)
    (let ((dom (libxml-parse-html-region (point-min) (point-max))))
      
      ;; Try multiple selectors for article content
      (or 
       ;; Try <article> tag
       (when-let ((article (car (dom-by-tag dom 'article))))
         (dom-texts article))
       
       ;; Try <main> tag
       (when-let ((main (car (dom-by-tag dom 'main))))
         (dom-texts main))
       
       ;; Try common content classes
       (when-let ((content (or (dom-by-class dom "article-content")
                              (dom-by-class dom "post-content")
                              (dom-by-class dom "entry-content"))))
         (dom-texts (car content)))
       
       ;; Fallback to body
       (when-let ((body (car (dom-by-tag dom 'body))))
         (dom-texts body))
       
       ""))))
```

### Extracting Metadata

Get title and other metadata from HTML:

```elisp
(defun my/extract-page-metadata (html)
  "Extract title and description from HTML."
  (with-temp-buffer
    (insert html)
    (let ((dom (libxml-parse-html-region (point-min) (point-max))))
      (list :title (or (dom-texts (car (dom-by-tag dom 'title)))
                      "Untitled")
            :description (or (dom-attr (car (dom-search 
                                            dom
                                            (lambda (node)
                                              (and (eq (dom-tag node) 'meta)
                                                  (equal (dom-attr node 'name) 
                                                        "description")))))
                                       'content)
                           "")))))
```

### Readability-Style Content Extraction

Filter noise and extract readable content:

```elisp
(defun my/extract-readable-content (html)
  "Extract main readable content, filtering scripts and ads."
  (with-temp-buffer
    (insert html)
    (let ((dom (libxml-parse-html-region (point-min) (point-max))))
      
      ;; Remove noise elements
      (dolist (tag '(script style nav header footer aside))
        (dolist (node (dom-by-tag dom tag))
          (dom-remove-node dom node)))
      
      ;; Remove by class (ads, comments, etc)
      (dolist (class '("advertisement" "sidebar" "comment" "footer"))
        (dolist (node (dom-by-class dom class))
          (dom-remove-node dom node)))
      
      ;; Extract from main content container
      (let ((main-node (or (car (dom-by-tag dom 'article))
                          (car (dom-by-tag dom 'main))
                          (car (dom-by-tag dom 'body)))))
        (when main-node
          (string-trim (dom-texts main-node)))))))
```

## Complete Integration Pattern: URL Capture with LLM Processing

### The Production-Ready Implementation

This complete example demonstrates the full workflow:

```elisp
(require 'org-capture)
(require 'gptel)

;; Configure gptel
(setq gptel-model 'claude-3-5-sonnet-20241022
      gptel-backend (gptel-make-anthropic "Claude"
                      :stream t
                      :key #'my-get-anthropic-key))

;; Capture template
(add-to-list 'org-capture-templates
             '("w" "Web Article" entry
               (file "~/org/articles.org")
               "* %^{Title}
:PROPERTIES:
:URL: %^{URL}
:CAPTURED: %U
:STATUS: processing
:END:

%?
"
               :after-finalize my/process-captured-url
               :empty-lines 1))

;; Main processing function
(defun my/process-captured-url ()
  "Process the last captured URL entry with AI."
  (when (and (not org-note-abort)
             (equal (plist-get org-capture-plist :key) "w"))
    ;; Small delay to ensure capture is fully finalized
    (run-with-timer 0.1 nil #'my/async-url-processing)))

;; Async processing orchestrator
(defun my/async-url-processing ()
  "Fetch URL and process with LLM asynchronously."
  (save-excursion
    (bookmark-jump "org-capture-last-stored")
    (let ((url (org-entry-get nil "URL"))
          (marker (point-marker)))
      
      (unless url
        (message "No URL property found")
        (return))
      
      (message "Fetching: %s" url)
      (org-entry-put nil "STATUS" "fetching")
      
      ;; Fetch URL asynchronously
      (my/fetch-url-async url
        ;; Success callback
        (lambda (html-content)
          (my/process-html-content html-content marker))
        
        ;; Error callback
        (lambda (error)
          (save-excursion
            (org-with-point-at marker
              (org-entry-put nil "STATUS" "fetch-error")
              (org-entry-put nil "ERROR" (format "%s" error))
              (message "Failed to fetch URL: %s" error)))
          (set-marker marker nil))))))

;; HTML processing
(defun my/process-html-content (html-content marker)
  "Extract content from HTML and send to LLM."
  (let* ((metadata (my/extract-page-metadata html-content))
         (clean-text (my/extract-readable-content html-content))
         (title (plist-get metadata :title)))
    
    (save-excursion
      (org-with-point-at marker
        (org-entry-put nil "STATUS" "processing-ai")
        (org-entry-put nil "EXTRACTED_TITLE" title)))
    
    ;; Process with LLM
    (my/llm-analyze-content clean-text marker)))

;; LLM analysis
(defun my/llm-analyze-content (text marker)
  "Analyze TEXT with LLM and update entry at MARKER."
  
  ;; First request: Generate summary
  (gptel-request text
    :system "Summarize this article in 2-3 clear sentences. 
Focus on the main thesis and key insights."
    :callback
    (lambda (summary info)
      (when summary
        (save-excursion
          (org-with-point-at marker
            (org-entry-put nil "AI_SUMMARY" summary)))
        
        ;; Second request: Extract tags
        (my/extract-and-save-tags text marker)))))

;; Tag extraction
(defun my/extract-and-save-tags (text marker)
  "Extract tags from TEXT and save to entry at MARKER."
  (gptel-request text
    :system "Analyze this content and extract 3-5 relevant topic tags.
Return ONLY comma-separated tags (e.g., 'machine-learning, python, ai').
No explanation, no extra formatting."
    :callback
    (lambda (tag-response info)
      (when tag-response
        (let ((tags (split-string (string-trim tag-response) "," t)))
          (save-excursion
            (org-with-point-at marker
              ;; Save as property
              (org-entry-put nil "AI_TAGS" 
                           (mapconcat #'string-trim tags " "))
              
              ;; Also add as org tags
              (org-set-tags (append (org-get-tags) 
                                  (mapcar #'string-trim tags)))
              
              ;; Mark complete
              (org-entry-put nil "STATUS" "completed")
              (org-entry-put nil "PROCESSED_AT" 
                           (format-time-string "[%Y-%m-%d %H:%M]"))
              
              (message "AI processing complete")))))
      
      ;; Clean up marker
      (set-marker marker nil))))
```

### Org-Protocol Integration for Browser Capture

Enable capturing from browser with automatic AI processing:

```elisp
;; org-protocol setup
(require 'org-protocol)

;; Custom protocol handler
(defun my/org-protocol-capture-ai (info)
  "Capture web page with AI processing via org-protocol."
  (let* ((url (plist-get info :url))
         (title (plist-get info :title))
         (selection (plist-get info :body))
         (org-capture-entry
          `("p" "Protocol AI" entry
            (file "~/org/bookmarks.org")
            ,(concat "* " title "\n"
                    ":PROPERTIES:\n"
                    ":URL: " url "\n"
                    ":CAPTURED: %U\n"
                    ":STATUS: queued\n"
                    ":END:\n\n"
                    (if selection 
                        (concat "** Selected Text\n" selection "\n\n")
                      "")
                    "%?")
            :after-finalize my/process-captured-url
            :immediate-finish t)))
    (org-capture nil "p")))

;; Register protocol
(add-to-list 'org-protocol-protocol-alist
             '("capture-ai"
               :protocol "capture-ai"
               :function my/org-protocol-capture-ai))

;; Browser bookmarklet:
;; javascript:location.href='org-protocol://capture-ai?url='+encodeURIComponent(location.href)+'&title='+encodeURIComponent(document.title)+'&body='+encodeURIComponent(window.getSelection().toString())
```

## Best Practices for Async Operations

### Always Use Non-Blocking Patterns

**Never block the main thread.** Use `url-retrieve` not `url-retrieve-synchronously`. Set `:stream nil` in gptel-request for predictable callbacks but ensure callback handles async updates. For CPU-intensive elisp, use `emacs-async` library.

### Marker Management is Critical

Markers track positions across buffer changes:

```elisp
(defun my/safe-marker-usage (marker operation-fn)
  "Use MARKER safely with cleanup."
  (unwind-protect
      (when (and marker (marker-position marker))
        (save-excursion
          (org-with-point-at marker
            (funcall operation-fn))))
    ;; Always clean up
    (when marker
      (set-marker marker nil))))
```

### Status Property Pattern

Track processing state for debugging and recovery:

```elisp
;; State machine: queued → fetching → processing-ai → completed
(defun my/set-processing-status (marker status &optional error-msg)
  "Update processing status at MARKER."
  (save-excursion
    (org-with-point-at marker
      (org-entry-put nil "STATUS" status)
      (org-entry-put nil "UPDATED_AT" 
                   (format-time-string "[%Y-%m-%d %H:%M]"))
      (when error-msg
        (org-entry-put nil "ERROR" error-msg)))))
```

### Error Recovery with Retry Logic

Handle transient failures gracefully:

```elisp
(defun my/retry-llm-request (text marker max-attempts)
  "Retry LLM request up to MAX-ATTEMPTS times."
  (let ((attempts 0))
    (cl-labels ((try-request ()
                  (setq attempts (1+ attempts))
                  (gptel-request text
                    :callback
                    (lambda (response info)
                      (if response
                          (my/save-result response marker)
                        (if (< attempts max-attempts)
                            (progn
                              (message "Retry %d/%d after error" 
                                      attempts max-attempts)
                              (run-with-timer 2 nil #'try-request))
                          (my/set-processing-status 
                           marker "error" 
                           (format "Failed after %d attempts" 
                                  max-attempts))))))))
      (try-request))))
```

### Batch Processing for Multiple Entries

Process queued entries periodically:

```elisp
(defun my/process-queued-entries ()
  "Process all entries with STATUS=queued."
  (interactive)
  (let ((processed 0))
    (org-map-entries
     (lambda ()
       (let ((url (org-entry-get nil "URL"))
             (marker (point-marker)))
         (when url
           (setq processed (1+ processed))
           (my/async-url-processing-from-marker marker))))
     "STATUS=\"queued\""
     (list "~/org/articles.org"))
    (message "Started processing %d queued entries" processed)))

;; Run automatically
(run-with-idle-timer 300 t #'my/process-queued-entries)
```

## Property Structure for Tags and Summaries

### Recommended Property Schema

```org
* Article Title
:PROPERTIES:
:URL: https://example.com/article
:CAPTURED: [2025-10-04 Sat 14:30]
:STATUS: completed
:PROCESSED_AT: [2025-10-04 Sat 14:32]
:AI_MODEL: claude-3-5-sonnet-20241022
:AI_SUMMARY: Two-sentence summary of the article content...
:AI_TAGS: machine-learning deep-learning python
:AI_CONFIDENCE: 0.89
:WORD_COUNT: 2453
:READING_TIME: 10 minutes
:END:
```

### Property Naming Conventions

**Use consistent prefixes** for related properties: `AI_*` for LLM-generated metadata, `URL_*` for fetch-related data, `PROC_*` for processing metadata. **Keep names uppercase** for tradition though case-insensitive. **Use underscores not hyphens** for multi-word properties.

### Property Manipulation Functions

```elisp
;; Set multiple properties atomically
(defun my/set-ai-metadata (marker metadata-plist)
  "Set all AI metadata properties at MARKER."
  (save-excursion
    (org-with-point-at marker
      (org-entry-put nil "AI_SUMMARY" 
                   (plist-get metadata-plist :summary))
      (org-entry-put nil "AI_TAGS" 
                   (plist-get metadata-plist :tags))
      (org-entry-put nil "AI_MODEL" 
                   (plist-get metadata-plist :model))
      (org-entry-put nil "AI_CONFIDENCE" 
                   (format "%.2f" (plist-get metadata-plist :confidence)))
      (org-entry-put nil "STATUS" "completed"))))

;; Get property with inheritance
(defun my/get-url-for-entry ()
  "Get URL for current entry, checking parents if needed."
  (or (org-entry-get nil "URL")
      (org-entry-get nil "URL" t)))  ; t enables inheritance
```

### Querying Properties with org-ql

Search and aggregate based on properties:

```elisp
(require 'org-ql)

;; Find all completed AI-processed entries
(org-ql-select (org-agenda-files)
  '(and (property "STATUS" "completed")
        (property "AI_SUMMARY"))
  :action #'org-get-heading)

;; Find entries needing reprocessing
(org-ql-select "~/org/articles.org"
  '(and (property "URL")
        (or (not (property "AI_SUMMARY"))
            (property "STATUS" "error")))
  :action (lambda () (point-marker)))
```

## Existing Projects and Reference Implementations

### gptel - The Gold Standard

**gptel** is the most mature LLM integration for Emacs. Its programmatic API (`gptel-request`) provides the foundation for automated workflows. Study the [gptel-quick](https://github.com/karthink/gptel-quick) package for clean examples of non-interactive usage.

### org-ai - Org-Native Approach

**org-ai** uses special blocks (`#+begin_ai...#+end_ai`) for inline AI interaction within org documents. While different from your capture-based approach, its property-based configuration system (`#+PROPERTY: temperature 0.7`) offers patterns for persistent LLM settings.

### gptel-got - Tool Use Example

**gptel-got** demonstrates providing tools that LLMs can call to query org files autonomously. Relevant if you later want AI assistants that can search your captured content to answer questions.

### Integration Pattern Comparison

**Inline blocks** (org-ai style) are reproducible and visible but less flexible. **Universal buffer integration** (gptel style) works anywhere and handles arbitrary workflows. **Capture-based automation** combines both: structured capture with flexible async processing.

## Complete Working Example: Minimal Viable Implementation

```elisp
;;;; Minimal AI-Enhanced URL Capture
;;;; Requires: gptel, org-capture

(require 'gptel)
(require 'org-capture)

;; Configure gptel (adjust for your LLM)
(setq gptel-model 'gpt-4o-mini
      gptel-api-key #'my-openai-key)

;; Capture template
(setq org-capture-templates
      '(("u" "URL + AI" entry
         (file "~/org/urls.org")
         "* %^{Title}\n:PROPERTIES:\n:URL: %^{URL}\n:STATUS: processing\n:END:\n"
         :after-finalize my/url-ai-process)))

;; Processing trigger
(defun my/url-ai-process ()
  (when (equal (plist-get org-capture-plist :key) "u")
    (run-with-timer 0.1 nil #'my/url-fetch-and-analyze)))

;; Fetch and analyze
(defun my/url-fetch-and-analyze ()
  (save-excursion
    (bookmark-jump "org-capture-last-stored")
    (let ((url (org-entry-get nil "URL"))
          (marker (point-marker)))
      (url-retrieve url
        (lambda (status)
          (goto-char (point-min))
          (re-search-forward "^\r?\n\r?\n")
          (let ((html (buffer-substring (point) (point-max))))
            (kill-buffer)
            (my/llm-process html marker)))))))

;; LLM processing
(defun my/llm-process (html marker)
  (gptel-request html
    :system "Summarize this webpage in 2 sentences and suggest 3 tags (comma-separated)."
    :callback
    (lambda (response info)
      (when response
        (save-excursion
          (org-with-point-at marker
            (org-entry-put nil "AI_RESULT" response)
            (org-entry-put nil "STATUS" "done")))
        (set-marker marker nil)))))
```

This 40-line implementation provides the complete workflow: capture, fetch, analyze, and update. Extend with error handling, content extraction, and structured tagging as needed.

## Advanced Patterns and Optimizations

### Streaming Responses for Long Content

Enable streaming to show partial results:

```elisp
(defun my/stream-summary-to-entry (text marker)
  "Stream LLM summary directly to org entry."
  (save-excursion
    (org-with-point-at marker
      (goto-char (point-max))
      (insert "\n** AI Summary\n")
      (let ((insert-pos (point)))
        (gptel-request text
          :system "Provide a detailed summary."
          :stream t
          :buffer (current-buffer)
          :position insert-pos)))))
```

### Multi-Stage Processing Pipeline

Chain multiple LLM calls for richer analysis:

```elisp
(defun my/multi-stage-analysis (text marker)
  "Perform multi-stage LLM analysis."
  ;; Stage 1: Summarize
  (gptel-request text
    :system "Summarize in 2-3 sentences."
    :callback
    (lambda (summary info)
      (save-excursion
        (org-with-point-at marker
          (org-entry-put nil "AI_SUMMARY" summary)))
      
      ;; Stage 2: Extract key concepts
      (gptel-request text
        :system "List 5 key concepts or terms."
        :callback
        (lambda (concepts info)
          (save-excursion
            (org-with-point-at marker
              (org-entry-put nil "AI_CONCEPTS" concepts)))
          
          ;; Stage 3: Generate questions
          (gptel-request text
            :system "Generate 3 thought-provoking questions about this content."
            :callback
            (lambda (questions info)
              (save-excursion
                (org-with-point-at marker
                  (org-entry-put nil "AI_QUESTIONS" questions)
                  (org-entry-put nil "STATUS" "completed")))
              (set-marker marker nil))))))))
```

### Caching for Expensive Operations

Cache LLM results to avoid reprocessing:

```elisp
(defvar my/llm-cache (make-hash-table :test 'equal)
  "Cache for LLM results keyed by content hash.")

(defun my/cached-llm-request (text system-msg callback)
  "Request with caching based on content hash."
  (let ((cache-key (secure-hash 'sha256 (concat text system-msg))))
    (if-let ((cached (gethash cache-key my/llm-cache)))
        (funcall callback cached nil)
      (gptel-request text
        :system system-msg
        :callback
        (lambda (response info)
          (when response
            (puthash cache-key response my/llm-cache))
          (funcall callback response info))))))
```

## Debugging and Troubleshooting

### Enable Comprehensive Logging

```elisp
;; Enable gptel logging
(setq gptel-log-level 'debug)

;; Add custom logging to your functions
(defun my/log-processing (marker message)
  "Log processing events to *AI-Capture-Log* buffer."
  (with-current-buffer (get-buffer-create "*AI-Capture-Log*")
    (goto-char (point-max))
    (insert (format "[%s] Marker %s: %s\n"
                    (format-time-string "%H:%M:%S")
                    marker
                    message))))
```

### Inspect Capture Context

```elisp
(defun my/debug-capture-hook ()
  "Debug hook showing capture context."
  (message "Key: %s, Description: %s, Aborted: %s"
           (plist-get org-capture-plist :key)
           (plist-get org-capture-plist :description)
           org-note-abort))

(add-hook 'org-capture-after-finalize-hook #'my/debug-capture-hook)
```

### Manual Reprocessing

```elisp
(defun my/reprocess-entry-at-point ()
  "Manually reprocess the org entry at point."
  (interactive)
  (let ((url (org-entry-get nil "URL"))
        (marker (point-marker)))
    (if url
        (progn
          (org-entry-put nil "STATUS" "reprocessing")
          (my/async-url-processing-from-marker marker))
      (message "No URL property found"))))
```

## Key Resources and Documentation

**Official Manuals**: [Org Capture](https://orgmode.org/manual/Capture.html), [Template Expansion](https://orgmode.org/manual/Template-expansion.html). **gptel Repository**: [github.com/karthink/gptel](https://github.com/karthink/gptel) with comprehensive wiki. **Emacs Lisp Reference**: `(info "(elisp) Top")` especially sections on processes and async operations.

**Example Projects**: gptel-quick for clean programmatic usage, org-ai for org-native AI blocks, gptel-got for tool-use patterns, org-capture-extension for browser integration baseline.

## Conclusion: Production Architecture Considerations

The capture-process-enrich architecture scales well with proper async patterns. Start with the minimal 40-line implementation and add features incrementally: error handling, retry logic, multi-stage pipelines, batch processing, and caching. The bookmark mechanism (`org-capture-last-stored`) reliably connects capture to async updates. Property-based status tracking enables recovery and debugging. Consider rate limiting for API calls, timeout handling for slow connections, and graceful degradation when LLMs are unavailable.

This implementation pattern works for any async post-processing, not just LLMs—image generation, external API calls, database lookups, or computationally expensive analysis all fit this architecture.