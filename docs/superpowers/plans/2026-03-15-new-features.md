# New Features Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add eight high-value features to org-capture-ai in priority order: duplicate detection, key takeaways, reading time, content-type routing, Archive.org fallback, related-entry linking, quote capture, and semantic search.

**Architecture:** All features add to `org-capture-ai.el` only (no new files), extending the existing defcustom/defun/ERT pattern. Features 1–2 integrate into the `org-capture-ai--llm-analyze` pipeline and are implemented first because they deliver immediate value with low risk. Features 3–8 are documented for future implementation.

**Tech Stack:** Emacs Lisp, ERT, gptel, org-mode properties drawers, cl-lib

---

## Chunk 1: Duplicate Detection

### Task 1: Duplicate URL Detection

**Files:**
- Modify: `org-capture-ai.el` — add defcustom (~line 217), add `org-capture-ai--find-duplicate`, modify `org-capture-ai--async-process` (~line 769)
- Modify: `org-capture-ai-test-helpers.el` — add helper for creating completed entries
- Modify: `org-capture-ai-regression-test.el` — add two regression tests

The duplicate check happens in `org-capture-ai--async-process`, right after reading the URL property and before starting the fetch.  A new helper `org-capture-ai--find-duplicate` searches configured files for a STATUS=completed entry with a matching URL.  If found, behavior is governed by `org-capture-ai-duplicate-action`.

- [ ] **Step 1: Verify baseline tests pass**

  Run: `./run-tests.sh`
  Expected: All suites pass

- [ ] **Step 2: Add the defcustom**

  In `org-capture-ai.el`, after the `org-capture-ai-batch-concurrency` defcustom (around line 217), add:

  ```elisp
  (defcustom org-capture-ai-duplicate-action 'warn
    "Action to take when capturing a URL that already exists as a completed entry.
  - `warn': Log a warning and continue processing (default).  The new entry
    will be processed normally; the user is notified via the log and echo area.
  - `skip': Set STATUS to \"duplicate\" and stop processing immediately.  Use
    this to avoid storing identical bookmarks.
  - `update': Continue processing normally (same as `warn') — reserved for
    a future update-in-place implementation."
    :type '(choice (const :tag "Warn and continue" warn)
                   (const :tag "Skip (set STATUS=duplicate)" skip)
                   (const :tag "Update existing entry" update))
    :group 'org-capture-ai)
  ```

- [ ] **Step 3: Add org-capture-ai--find-duplicate**

  In `org-capture-ai.el`, before `org-capture-ai--async-process` (around line 769), add:

  ```elisp
  (defun org-capture-ai--find-duplicate (url)
    "Search configured files for a completed entry whose URL property equals URL.
  Returns the heading title string of the first match, or nil if none found.
  Only entries with STATUS=completed are considered duplicates; entries that
  are still processing, queued, or errored are ignored."
    (let ((files (or org-capture-ai-files (list org-capture-ai-default-file)))
          (result nil))
      (dolist (file files)
        (when (and (file-exists-p file) (not result))
          (org-map-entries
           (lambda ()
             (when (equal (org-entry-get nil "URL") url)
               (setq result (org-get-heading t t t t))))
           "STATUS=\"completed\""
           (list file))))
      result))
  ```

- [ ] **Step 4: Add duplicate check to org-capture-ai--async-process**

  In `org-capture-ai--async-process`, find this block (around line 781):

  ```elisp
        (unless url
          (org-capture-ai--log "No URL property found")
          (message "org-capture-ai: No URL property found")
          (cl-return-from org-capture-ai--async-process))

        (message "org-capture-ai: Fetching %s" url)
  ```

  Replace with:

  ```elisp
        (unless url
          (org-capture-ai--log "No URL property found")
          (message "org-capture-ai: No URL property found")
          (cl-return-from org-capture-ai--async-process))

        ;; Check for duplicate before fetching
        (when-let ((dup-heading (org-capture-ai--find-duplicate url)))
          (org-capture-ai--log "Duplicate URL detected: %s (existing: \"%s\")"
                               url dup-heading)
          (pcase org-capture-ai-duplicate-action
            ('skip
             (org-capture-ai--set-status marker "duplicate")
             (setq org-capture-ai--processing-markers
                   (delq (marker-position marker) org-capture-ai--processing-markers))
             (set-marker marker nil)
             (message "org-capture-ai: Duplicate URL skipped (already captured: \"%s\")"
                      dup-heading)
             (cl-return-from org-capture-ai--async-process))
            ((or 'warn 'update)
             (message "org-capture-ai: Warning: URL already captured as \"%s\"" dup-heading))))

        (message "org-capture-ai: Fetching %s" url)
  ```

- [ ] **Step 5: Add test helper for completed entries**

  In `org-capture-ai-test-helpers.el`, after `org-capture-ai-test--create-processing-entry`, add:

  ```elisp
  (defun org-capture-ai-test--create-completed-entry (url title)
    "Create a completed entry with URL and TITLE in the test buffer.
  Returns a marker pointing to the entry.  Used to set up duplicate-detection tests."
    (goto-char (point-max))
    (insert (format "** %s\n" title))
    (insert ":PROPERTIES:\n")
    (insert ":URL: " url "\n")
    (insert ":CAPTURED: [2025-10-27 Mon 14:00]\n")
    (insert ":STATUS: completed\n")
    (insert ":END:\n\n")
    (org-back-to-heading t)
    (point-marker))
  ```

- [ ] **Step 6: Write failing tests**

  In `org-capture-ai-regression-test.el`, add these two tests:

  ```elisp
  (ert-deftest org-capture-ai-regression-20260315-duplicate-skip ()
    "Regression: Duplicate URL with skip action sets STATUS=duplicate.

  Bug: Without duplicate detection, capturing the same URL twice creates
  redundant entries.

  Fix: org-capture-ai--find-duplicate detects matching completed entries;
  with duplicate-action=skip, processing halts and STATUS=duplicate is set.

  Date: 2026-03-15
  File: org-capture-ai.el"
    (org-capture-ai-test--with-mocked-env
     (let ((org-capture-ai-duplicate-action 'skip)
           (test-url "https://example.com/test-article"))
       (with-current-buffer (find-file-noselect org-capture-ai-test--temp-file)

         ;; Create the existing completed entry for the same URL
         (org-capture-ai-test--create-completed-entry test-url "Existing Article")

         ;; Now capture the same URL again
         (let* ((marker (org-capture-ai-test--create-processing-entry test-url))
                (entry-pos (marker-position marker)))

           (org-capture-ai--async-process marker)

           ;; Wait briefly for sync processing
           (sit-for 0.2)

           ;; Navigate to the new entry
           (goto-char entry-pos)
           (org-back-to-heading t)

           ;; Should be marked as duplicate, not completed
           (should (equal "duplicate" (org-entry-get nil "STATUS"))))))))

  (ert-deftest org-capture-ai-regression-20260315-duplicate-warn ()
    "Regression: Duplicate URL with warn action continues processing.

  Bug: The warn action should allow processing to proceed normally so the
  user sees the warning but still gets a processed entry.

  Fix: With duplicate-action=warn, only a message is emitted; processing
  continues and STATUS reaches completed.

  Date: 2026-03-15
  File: org-capture-ai.el"
    (org-capture-ai-test--with-mocked-env
     (let ((org-capture-ai-duplicate-action 'warn)
           (test-url "https://example.com/test-article"))
       (with-current-buffer (find-file-noselect org-capture-ai-test--temp-file)

         ;; Create the existing completed entry for the same URL
         (org-capture-ai-test--create-completed-entry test-url "Existing Article")

         ;; Capture the same URL again
         (let* ((marker (org-capture-ai-test--create-processing-entry test-url))
                (entry-pos (marker-position marker)))

           (org-capture-ai--async-process marker)
           (org-capture-ai-test--wait-for-processing marker)

           ;; Navigate back
           (goto-char entry-pos)
           (org-back-to-heading t)

           ;; Processing should complete normally despite duplicate
           (should (equal "completed" (org-entry-get nil "STATUS"))))))))
  ```

- [ ] **Step 7: Run tests to verify they fail**

  Run: `./run-tests.sh regression`
  Expected: Both new tests fail (feature not implemented yet)

- [ ] **Step 8: Run tests to verify implementation passes**

  After completing steps 2–5, run: `./run-tests.sh`
  Expected: All tests pass including the two new tests

- [ ] **Step 9: Commit**

  ```bash
  git add org-capture-ai.el org-capture-ai-test-helpers.el org-capture-ai-regression-test.el
  git commit -m "Add duplicate URL detection with configurable action"
  ```

---

## Chunk 2: Key Takeaways

### Task 2: Key Takeaways Extraction

**Files:**
- Modify: `org-capture-ai.el` — add defcustom, add `org-capture-ai-llm-extract-takeaways`, add `org-capture-ai--finalize-entry`, restructure `org-capture-ai--llm-analyze`
- Modify: `org-capture-ai-test-helpers.el` — add `:takeaways` mock response, add dispatch branch
- Modify: `org-capture-ai-regression-test.el` — add two regression tests

Takeaways are extracted as a third LLM call chained after tag extraction.  Completion logic is extracted into `org-capture-ai--finalize-entry` so both the two-step path (takeaways disabled) and three-step path (enabled) share the same finalization code.  Takeaways are stored in the TAKEAWAYS property as pipe-separated single-sentence insights.

- [ ] **Step 1: Add the defcustom**

  In `org-capture-ai.el`, after `org-capture-ai-duplicate-action` defcustom, add:

  ```elisp
  (defcustom org-capture-ai-extract-takeaways t
    "When non-nil, extract 3-5 key takeaways in addition to summary and tags.
  Takeaways are stored in the TAKEAWAYS property as pipe-separated sentences.
  Each takeaway is a single-sentence distillation of an important insight.
  Set to nil to disable this step and reduce LLM API call count by one."
    :type 'boolean
    :group 'org-capture-ai)
  ```

- [ ] **Step 2: Add mock takeaways response and dispatch**

  In `org-capture-ai-test-helpers.el`, update `org-capture-ai-test--mock-llm-responses` to add a `:takeaways` key:

  ```elisp
  (defvar org-capture-ai-test--mock-llm-responses
    '((:summary . "TITLE: Test Title\nSUMMARY: This is a test summary. It has multiple sentences. Testing works.")
      (:tags . "article, test, emacs")
      (:takeaways . "1. Testing is important for reliability.\n2. Emacs is highly extensible.\n3. Async code requires careful design."))
    "Default mock LLM responses.")
  ```

  In `org-capture-ai-test--mock-gptel-request`, add a dispatch branch for takeaways. Find:

  ```elisp
    (let ((response (cond
                     ((string-match "title and.*summary" system-msg)
                      (cdr (assq :summary org-capture-ai-test--mock-llm-responses)))
                     ((string-match "tags" system-msg)
                      (cdr (assq :tags org-capture-ai-test--mock-llm-responses)))
                     (t "mock response"))))
  ```

  Replace with:

  ```elisp
    (let ((response (cond
                     ((string-match "title and.*summary" system-msg)
                      (cdr (assq :summary org-capture-ai-test--mock-llm-responses)))
                     ((string-match "tags" system-msg)
                      (cdr (assq :tags org-capture-ai-test--mock-llm-responses)))
                     ((string-match "takeaway" system-msg)
                      (cdr (assq :takeaways org-capture-ai-test--mock-llm-responses)))
                     (t "mock response"))))
  ```

- [ ] **Step 3: Add org-capture-ai-llm-extract-takeaways**

  In `org-capture-ai.el`, after `org-capture-ai-llm-extract-tags` (after line 711), add:

  ```elisp
  (defun org-capture-ai-llm-extract-takeaways (text callback)
    "Extract 3-5 key takeaways from TEXT using the configured LLM.
  Calls CALLBACK with a list of takeaway strings on success, or nil on failure.
  Each takeaway is a single sentence distilling one important insight.
  The LLM is asked to return a numbered list; lines not matching the
  numbered-list pattern are silently discarded."
    (let ((prompt "Extract 3-5 key takeaways from this content.
  Each takeaway must be a single, self-contained sentence capturing one important insight.
  Return ONLY a numbered list, one takeaway per line, no extra text.
  Example format:
  1. First key insight as a complete sentence.
  2. Second key insight as a complete sentence.
  3. Third key insight as a complete sentence."))
      (org-capture-ai-llm-request text prompt
        (lambda (response _info)
          (if response
              (let ((takeaways nil))
                (dolist (line (split-string (string-trim response) "\n" t))
                  (when (string-match "^[0-9]+\\.[ \t]+\\(.*\\)" line)
                    (push (string-trim (match-string 1 line)) takeaways)))
                (funcall callback (nreverse takeaways)))
            (funcall callback nil))))))
  ```

- [ ] **Step 4: Extract org-capture-ai--finalize-entry**

  In `org-capture-ai.el`, before `org-capture-ai--llm-analyze`, add:

  ```elisp
  (defun org-capture-ai--finalize-entry (marker tags)
    "Complete processing for the entry at MARKER.
  Sets STATUS to \"completed\" and records PROCESSED_AT when TAGS is non-nil.
  Sets STATUS to \"error\" when TAGS is nil (tag extraction failed).
  In all cases, removes MARKER from `org-capture-ai--processing-markers'
  and invalidates it."
    (if tags
        (progn
          (org-capture-ai--set-status marker "completed")
          (save-excursion
            (org-with-point-at marker
              (org-back-to-heading t)
              (org-entry-put nil "PROCESSED_AT"
                             (format-time-string "[%Y-%m-%d %a %H:%M]"))))
          (message "org-capture-ai: Processing complete"))
      (org-capture-ai--set-status marker "error" "Tag extraction failed"))
    (setq org-capture-ai--processing-markers
          (delq (marker-position marker) org-capture-ai--processing-markers))
    (org-capture-ai--log "Removed marker %d from processing list" (marker-position marker))
    (set-marker marker nil))
  ```

- [ ] **Step 5: Restructure org-capture-ai--llm-analyze to add third step**

  In `org-capture-ai--llm-analyze`, find the tags extraction block starting with:

  ```elisp
          ;; Second: Extract tags
          (org-capture-ai-llm-extract-tags text
            (lambda (tags)
              (if tags
                  (save-excursion
                    (org-with-point-at marker
                      (org-back-to-heading t)

                      ;; Save as SUBJECT (Dublin Core) - sanitized
                      (org-entry-put nil "SUBJECT"
                                     (org-capture-ai--sanitize-property-value
                                      (mapconcat #'identity tags ", ")))

                      ;; Also add as org tags (removing duplicates)
                      (org-set-tags (delete-dups (append (org-get-tags) tags)))

                      ;; Mark complete
                      (org-capture-ai--set-status marker "completed")
                      (org-entry-put nil "PROCESSED_AT"
                                     (format-time-string "[%Y-%m-%d %a %H:%M]"))

                      (message "org-capture-ai: Processing complete")))
                (org-capture-ai--set-status marker "error" "Tag extraction failed"))

              ;; Clean up marker and remove from processing list
              (setq org-capture-ai--processing-markers
                    (delq (marker-position marker) org-capture-ai--processing-markers))
              (org-capture-ai--log "Removed marker %d from processing list" (marker-position marker))
              (set-marker marker nil)))))))))
  ```

  Replace with:

  ```elisp
          ;; Second: Extract tags
          (org-capture-ai-llm-extract-tags text
            (lambda (tags)
              (when tags
                (save-excursion
                  (org-with-point-at marker
                    (org-back-to-heading t)
                    ;; Save as SUBJECT (Dublin Core) - sanitized
                    (org-entry-put nil "SUBJECT"
                                   (org-capture-ai--sanitize-property-value
                                    (mapconcat #'identity tags ", ")))
                    ;; Also add as org tags (removing duplicates)
                    (org-set-tags (delete-dups (append (org-get-tags) tags))))))

              ;; Third: Extract takeaways (if enabled and tags succeeded)
              (if (and tags org-capture-ai-extract-takeaways)
                  (org-capture-ai-llm-extract-takeaways text
                    (lambda (takeaways)
                      (when takeaways
                        (save-excursion
                          (org-with-point-at marker
                            (org-back-to-heading t)
                            (org-entry-put nil "TAKEAWAYS"
                                           (org-capture-ai--sanitize-property-value
                                            (mapconcat #'identity takeaways " | "))))))
                      (org-capture-ai--finalize-entry marker tags)))
                (org-capture-ai--finalize-entry marker tags)))))))))
  ```

- [ ] **Step 6: Write failing tests**

  In `org-capture-ai-regression-test.el`, add:

  ```elisp
  (ert-deftest org-capture-ai-regression-20260315-takeaways-extracted ()
    "Regression: TAKEAWAYS property is set when extraction is enabled.

  Bug: Without takeaways feature, there is no way to get a quick overview
  of an article's key insights without reading the full summary.

  Fix: org-capture-ai-llm-extract-takeaways runs as a third LLM step after
  tags, storing results in TAKEAWAYS as pipe-separated sentences.

  Date: 2026-03-15
  File: org-capture-ai.el"
    (org-capture-ai-test--with-mocked-env
     (let ((org-capture-ai-extract-takeaways t))
       (with-current-buffer (find-file-noselect org-capture-ai-test--temp-file)
         (let* ((marker (org-capture-ai-test--create-processing-entry
                         "https://example.com/article"))
                (entry-pos (marker-position marker)))

           (org-capture-ai--async-process marker)
           (org-capture-ai-test--wait-for-processing marker)

           (goto-char entry-pos)
           (org-back-to-heading t)

           (should (equal "completed" (org-entry-get nil "STATUS")))
           (let ((takeaways (org-entry-get nil "TAKEAWAYS")))
             (should takeaways)
             ;; Should contain at least one pipe-separated takeaway
             (should (string-match-p "\\." takeaways))))))))

  (ert-deftest org-capture-ai-regression-20260315-takeaways-disabled ()
    "Regression: No TAKEAWAYS property when extraction is disabled.

  Bug: Users who want to reduce API costs should be able to skip takeaways.

  Fix: When org-capture-ai-extract-takeaways is nil, the third LLM call is
  skipped and TAKEAWAYS is not set.

  Date: 2026-03-15
  File: org-capture-ai.el"
    (org-capture-ai-test--with-mocked-env
     (let ((org-capture-ai-extract-takeaways nil))
       (with-current-buffer (find-file-noselect org-capture-ai-test--temp-file)
         (let* ((marker (org-capture-ai-test--create-processing-entry
                         "https://example.com/article"))
                (entry-pos (marker-position marker)))

           (org-capture-ai--async-process marker)
           (org-capture-ai-test--wait-for-processing marker)

           (goto-char entry-pos)
           (org-back-to-heading t)

           (should (equal "completed" (org-entry-get nil "STATUS")))
           (should (null (org-entry-get nil "TAKEAWAYS")))))))))
  ```

- [ ] **Step 7: Run tests to verify they fail**

  Run: `./run-tests.sh regression`
  Expected: Both new tests fail

- [ ] **Step 8: Run full test suite to verify implementation**

  After completing steps 1–5, run: `./run-tests.sh`
  Expected: All tests pass including all four new tests

- [ ] **Step 9: Commit**

  ```bash
  git add org-capture-ai.el org-capture-ai-test-helpers.el org-capture-ai-regression-test.el
  git commit -m "Add key takeaways extraction as third LLM pipeline step"
  ```

---

## Chunk 3: Reading Time Estimate (Future)

### Task 3: Reading Time Estimate

**Goal:** Add a `READING_TIME` property computed from word count without an LLM call.

**Files:**
- Modify: `org-capture-ai.el` — add defcustom `org-capture-ai-reading-wpm` (default 238), add `org-capture-ai--estimate-reading-time`, call from `org-capture-ai--process-html` after content extraction

**Key code:**
```elisp
(defcustom org-capture-ai-reading-wpm 238
  "Words per minute for reading time estimates (average adult silent reading rate)."
  :type 'integer
  :group 'org-capture-ai)

(defun org-capture-ai--estimate-reading-time (text)
  "Return a reading time string for TEXT (e.g. \"4 min\")."
  (let* ((word-count (length (split-string text nil t)))
         (minutes (max 1 (round (/ (float word-count) org-capture-ai-reading-wpm)))))
    (format "%d min" minutes)))
```

Call in `org-capture-ai--process-html` immediately after the truncation block:
```elisp
(org-entry-put nil "READING_TIME"
               (org-capture-ai--estimate-reading-time clean-text))
```

**Tests:** Verify READING_TIME is set; verify minimum of "1 min" for short content.

---

## Chunk 4: Content-Type-Aware Extraction (Future)

### Task 4: YouTube and PDF Routing

**Goal:** Detect YouTube URLs and PDF URLs, route to appropriate handlers instead of generic HTML extraction.

**Files:**
- Modify: `org-capture-ai.el` — add `org-capture-ai--detect-content-type`, add `org-capture-ai--extract-youtube-metadata`, modify `org-capture-ai--async-process` dispatch

**Content type detection:**
```elisp
(defun org-capture-ai--detect-content-type (url)
  "Return a symbol describing the content type of URL.
Returns `youtube', `pdf', or `html'."
  (cond
   ((string-match-p "\\(youtube\\.com/watch\\|youtu\\.be/\\)" url) 'youtube)
   ((string-match-p "\\.pdf\\(\\?\\|$\\)" url) 'pdf)
   (t 'html)))
```

For YouTube: extract video ID, use oEmbed API (no API key needed):
`https://www.youtube.com/oembed?url=<url>&format=json`

For PDF: fetch the PDF, use `pdftotext` if available, fall back to filename-based metadata.

**Tests:** Verify content-type detection for sample URLs; verify YouTube routing doesn't call generic fetch.

---

## Chunk 5: Archive.org Fallback (Future)

### Task 5: Wayback Machine Fallback

**Goal:** When the primary URL fetch fails, automatically retry using the Wayback Machine's latest snapshot.

**Files:**
- Modify: `org-capture-ai.el` — add `org-capture-ai-use-archive-fallback` defcustom, add `org-capture-ai--archive-url`, modify error path in `org-capture-ai--async-process`

**Key code:**
```elisp
(defcustom org-capture-ai-use-archive-fallback t
  "When non-nil, retry failed fetches via the Wayback Machine."
  :type 'boolean
  :group 'org-capture-ai)

(defun org-capture-ai--archive-url (url)
  "Return the Wayback Machine URL for the latest snapshot of URL."
  (format "https://web.archive.org/web/2/%s" url))
```

Modify the fetch error callback:
```elisp
(lambda (error)
  (if org-capture-ai-use-archive-fallback
      (progn
        (org-capture-ai--log "Primary fetch failed, trying Archive.org: %s" error)
        (org-capture-ai-fetch-url (org-capture-ai--archive-url url)
          (lambda (html-content)
            (org-capture-ai--process-html html-content url marker))
          (lambda (archive-error)
            (org-capture-ai--set-status marker "fetch-error"
              (format "Primary: %s; Archive: %s" error archive-error))
            (set-marker marker nil))))
    (org-capture-ai--set-status marker "fetch-error" (format "%s" error))
    (set-marker marker nil)))
```

**Tests:** Mock primary fetch to fail; verify archive URL is tried; verify double failure sets STATUS=fetch-error.

---

## Chunk 6: Related Entry Linking (Future)

### Task 6: Tag-Based Related Entry Suggestions

**Goal:** After processing, find existing completed entries that share tags with the new entry and store their headings in a RELATED property.

**Files:**
- Modify: `org-capture-ai.el` — add defcustom `org-capture-ai-link-related` (boolean, default nil), add `org-capture-ai--find-related-entries`, call from `org-capture-ai--finalize-entry`

**Key design:**
- Collect SUBJECT tags from the new entry
- Search completed entries for entries sharing ≥2 tags
- Store up to 3 matching heading titles in RELATED property (pipe-separated)
- Default off: requires scanning all entries, which is expensive for large files

---

## Chunk 7: Quote Capture via org-protocol (Future)

### Task 7: Selected Text Quote Capture

**Goal:** Support capturing a selected quote from a page alongside the URL via org-protocol.

**Files:**
- Modify: `org-capture-ai.el` — add `org-capture-ai-protocol-handler`, add capture template variant

**Key design:**
- Register an `org-protocol` handler for `org-capture-ai://quote?url=...&quote=...`
- Create a second capture template key (default "q") for quote captures
- Store the selected text in a QUOTE property and as a blockquote in the entry body
- Skip HTML fetch (quote already provides content); use the quote text for LLM analysis

---

## Chunk 8: Semantic Search (Future)

### Task 8: Embedding-Based Search

**Goal:** Enable `M-x org-capture-ai-search` to find entries semantically similar to a query.

**Files:**
- New: `org-capture-ai-search.el` — separate file due to scope
- Modify: `org-capture-ai.el` — add `org-capture-ai-build-index` command

**Key design:**
- Use gptel to generate embeddings for each entry's summary text
- Store embeddings in a sidecar file (`org-capture-ai-index.eld`)
- At search time, embed the query and compute cosine similarity against all stored embeddings
- Present top-N results in a completion buffer with jump-to-entry action
- Index is rebuilt incrementally: only entries without stored embeddings need processing

Note: Requires an LLM backend that supports embeddings (e.g., OpenAI text-embedding-3-small). Not all gptel backends support this; the feature should degrade gracefully when embeddings are unavailable.
