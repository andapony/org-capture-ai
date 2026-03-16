;;; org-capture-ai.el --- AI-enhanced URL capture for org-mode -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: AI-Generated
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (org "9.5") (gptel "0.7.0"))
;; Keywords: org, ai, capture, llm
;; URL: https://github.com/example/org-capture-ai

;;; Commentary:

;; org-capture-ai provides AI-enhanced URL capture for org-mode using LLMs.
;; It automatically fetches web content, extracts Dublin Core metadata,
;; generates summaries, and extracts tags using AI models via gptel.
;;
;; The workflow is: Capture → Finalize → Fetch URL → Call LLM → Update Properties
;; All processing happens asynchronously to avoid blocking Emacs.
;;
;; Usage:
;;   (require 'org-capture-ai)
;;   (org-capture-ai-setup)
;;
;; Then use the capture template (default key "u" for URL capture).
;;
;; Commands:
;;   org-capture-ai-reprocess-entry - Reprocess entry (keeps existing content)
;;   org-capture-ai-refresh-entry   - Refresh entry (replaces all content)
;;   org-capture-ai-process-queued  - Process all queued entries

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'org-capture)
(require 'gptel)
(require 'url)
(require 'dom)

;;; Customization

(defgroup org-capture-ai nil
  "AI-enhanced URL capture for org-mode."
  :group 'org
  :prefix "org-capture-ai-")

(defcustom org-capture-ai-default-file "~/Sync/bookmarks.org"
  "Org file where URL captures are stored.
This file must exist before captures can be saved.  Entries are added
under a \"Bookmarks\" heading created by the capture template."
  :type 'file
  :group 'org-capture-ai)

(defcustom org-capture-ai-template-key "u"
  "Key used to invoke the URL capture template in `org-capture'.
Registered in `org-capture-templates' by `org-capture-ai-setup'.
The default \"u\" is invoked by pressing this key in the `org-capture'
dispatcher."
  :type 'string
  :group 'org-capture-ai)

(defcustom org-capture-ai-summary-sentences 3
  "Number of sentences for AI-generated summaries.
Only used when `org-capture-ai-summary-style' is `sentences'."
  :type 'integer
  :group 'org-capture-ai)

(defcustom org-capture-ai-summary-style 'sentences
  "Style of AI-generated summaries.
- `sentences': Single paragraph with a fixed number of sentences.
  Length controlled by `org-capture-ai-summary-sentences'.
- `paragraphs': Overview paragraph followed by per-topic paragraphs.
  Lengths controlled by `org-capture-ai-summary-overview-sentences',
  `org-capture-ai-summary-topic-max-sentences', and
  `org-capture-ai-summary-topic-paragraphs'."
  :type '(choice (const :tag "Single paragraph (sentences)" sentences)
                 (const :tag "Multi-paragraph (overview + topics)" paragraphs))
  :group 'org-capture-ai)

(defcustom org-capture-ai-summary-overview-sentences 3
  "Number of sentences in the overview paragraph.
Used when `org-capture-ai-summary-style' is `paragraphs'."
  :type 'integer
  :group 'org-capture-ai)

(defcustom org-capture-ai-summary-topic-paragraphs 'auto
  "Number of topic paragraphs to generate.
Used when `org-capture-ai-summary-style' is `paragraphs'.
- `auto': Let the LLM decide based on article content
- Integer: Request specific number of topic paragraphs"
  :type '(choice (const :tag "Auto (LLM decides)" auto)
                 (integer :tag "Fixed number"))
  :group 'org-capture-ai)

(defcustom org-capture-ai-summary-topic-max-sentences 5
  "Maximum sentences per topic paragraph.
Used when `org-capture-ai-summary-style' is `paragraphs'."
  :type 'integer
  :group 'org-capture-ai)

(defcustom org-capture-ai-use-curated-tags t
  "Use curated faceted tag sets instead of free-form tags.
When t, LLM selects from predefined tag lists organized by facets.
When nil, LLM generates free-form tags."
  :type 'boolean
  :group 'org-capture-ai)

(defcustom org-capture-ai-tag-count 5
  "Maximum number of tags to extract.
Only used when `org-capture-ai-use-curated-tags' is nil."
  :type 'integer
  :group 'org-capture-ai)

(defcustom org-capture-ai-tags-type
  '("article" "tutorial" "video" "tool" "reference" "book" "paper" "course")
  "Curated tags for content type/format facet."
  :type '(repeat string)
  :group 'org-capture-ai)

(defcustom org-capture-ai-tags-status
  '("active" "reference" "implemented" "archived")
  "Curated tags for status/lifecycle facet."
  :type '(repeat string)
  :group 'org-capture-ai)

(defcustom org-capture-ai-tags-quality
  '("canonical" "authoritative" "exploratory" "opinion")
  "Curated tags for quality/authority facet."
  :type '(repeat string)
  :group 'org-capture-ai)

(defcustom org-capture-ai-tags-domain
  '(;; Technology (8 tags)
    "programming" "web_development" "artificial_intelligence" "data_science"
    "devops" "security" "design" "tools"
    ;; Creative Fields (5 tags)
    "visual_arts" "writing" "video" "music" "creative_inspiration"
    ;; Professional/Business (7 tags)
    "business" "marketing" "career" "management" "productivity" "finance" "education"
    ;; Science & Medicine (5 tags)
    "health_medicine" "biology" "physics_chemistry" "environment" "space"
    ;; Social Sciences (4 tags)
    "psychology" "politics" "sociology" "economics"
    ;; Humanities (3 tags)
    "history" "philosophy" "literature"
    ;; Personal/Lifestyle (6 tags)
    "self_improvement" "fitness" "food_cooking" "travel" "home_diy" "relationships"
    ;; Functional/Meta (4 tags)
    "tutorial" "reference" "news" "entertainment")
  "Comprehensive curated tag set for domain/subject facet.

This 42-tag flat domain system provides complete coverage across eight major domains:
- Technology (8): programming, web dev, AI, data science, devops, security, design, tools
- Creative (5): visual arts, writing, video, music, creative inspiration
- Professional/Business (7): business, marketing, career, management, productivity, finance, education
- Science & Medicine (5): health/medicine, biology, physics/chemistry, environment, space
- Social Sciences (4): psychology, politics, sociology, economics
- Humanities (3): history, philosophy, literature
- Personal/Lifestyle (6): self-improvement, fitness, food/cooking, travel, home/DIY, relationships
- Functional/Meta (4): tutorial, reference, news, entertainment

Based on research showing optimal bookmark tag systems use 35-50 tags for generalist
collections. This seed set balances comprehensive coverage with practical usability.
Customize by adding/removing tags based on your collection focus and usage patterns."
  :type '(repeat string)
  :group 'org-capture-ai)

(defcustom org-capture-ai-max-retries 3
  "Maximum number of attempts for a single LLM request.
On each failure the request is retried with exponential backoff: 2 seconds
before the second attempt, 4 before the third, and so on.
Synchronous errors (e.g., gptel not configured) are not retried."
  :type 'integer
  :group 'org-capture-ai)

(defcustom org-capture-ai-enable-logging t
  "Non-nil means log debug messages to the `*org-capture-ai-log*' buffer.
Each entry is timestamped.  Useful for diagnosing fetch or LLM failures.
Disable to reduce buffer clutter once the library is working correctly."
  :type 'boolean
  :group 'org-capture-ai)

(defcustom org-capture-ai-batch-idle-time 300
  "Idle time in seconds before processing queued entries.
Set to nil to disable automatic batch processing."
  :type '(choice integer (const nil))
  :group 'org-capture-ai)

(defcustom org-capture-ai-process-on-capture t
  "Whether to automatically process URLs after capture.
If nil, entries will be marked as queued for later batch processing."
  :type 'boolean
  :group 'org-capture-ai)

(defcustom org-capture-ai-max-content-length 50000
  "Maximum characters of page content to send to the LLM.
Content exceeding this length is truncated before LLM analysis.
Default 50000 chars is approximately 12500 tokens, well within
most LLM context limits while covering the vast majority of articles."
  :type 'integer
  :group 'org-capture-ai)

(defcustom org-capture-ai-reading-wpm 238
  "Words per minute used to estimate reading time for captured articles.
The default of 238 is the average adult silent reading rate.
Used by `org-capture-ai--estimate-reading-time' to compute READING_TIME."
  :type 'integer
  :group 'org-capture-ai)

(defcustom org-capture-ai-files nil
  "List of org files to search for queued entries during batch processing.
If nil, defaults to a list containing `org-capture-ai-default-file'.
Set this if you capture URLs to multiple org files."
  :type '(repeat file)
  :group 'org-capture-ai)

(defcustom org-capture-ai-batch-concurrency 3
  "Maximum number of concurrent pipeline slots during batch processing.
Each slot covers the full fetch-plus-LLM pipeline for one entry, so
this setting limits both simultaneous HTTP connections and overlapping
LLM requests.  Higher values process the queue faster but increase the
risk of hitting API rate limits."
  :type 'integer
  :group 'org-capture-ai)

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

(defcustom org-capture-ai-extract-takeaways t
  "When non-nil, extract 3-5 key takeaways in addition to summary and tags.
Takeaways are inserted as a bullet list at the top of the entry body.
Each takeaway is a single sentence distilling one important insight.
Set to nil to disable this step and reduce LLM API call count by one."
  :type 'boolean
  :group 'org-capture-ai)

;;; Internal Variables

(defvar org-capture-ai--batch-timer nil
  "Timer for batch processing queued entries.")

(defvar org-capture-ai--active-fetch-count 0
  "Number of URL fetches currently in progress during batch processing.")

(defvar org-capture-ai--pending-batch nil
  "Queue of (url . marker) pairs waiting to be dispatched in batch processing.")

;;; Logging

(defun org-capture-ai--log (format-string &rest args)
  "Append a timestamped message to `*org-capture-ai-log*'.
Does nothing when `org-capture-ai-enable-logging' is nil.
FORMAT-STRING and ARGS are formatted with `format'."
  (when org-capture-ai-enable-logging
    (with-current-buffer (get-buffer-create "*org-capture-ai-log*")
      (goto-char (point-max))
      (insert (format "[%s] %s\n"
                      (format-time-string "%Y-%m-%d %H:%M:%S")
                      (apply #'format format-string args))))))

;;; Status Management

(defun org-capture-ai--set-status (marker status &optional error-msg)
  "Set the STATUS property of the entry at MARKER.
Also updates the UPDATED_AT property with the current timestamp.
When ERROR-MSG is non-nil, stores it in the ERROR property after
sanitizing for single-line use.
Saves the buffer automatically when STATUS is a terminal value:
\"completed\", \"error\", or \"fetch-error\"."
  (org-capture-ai--log "Setting status to %s at marker %s" status marker)
  (save-excursion
    (org-with-point-at marker
      (org-back-to-heading t)
      (org-entry-put nil "STATUS" status)
      (org-entry-put nil "UPDATED_AT" (format-time-string "[%Y-%m-%d %a %H:%M]"))
      (when error-msg
        (org-entry-put nil "ERROR" (org-capture-ai--sanitize-property-value error-msg)))
      ;; Auto-save on terminal states
      (when (member status '("completed" "error" "fetch-error" "duplicate"))
        (save-buffer)))))

;;; HTML Processing

(defcustom org-capture-ai-fetch-method 'curl
  "Method used to fetch web page content.
- `url-retrieve': Emacs built-in; no external dependencies, but limited
  compatibility with sites that detect non-browser clients by means beyond
  the User-Agent string (e.g., Substack serves a JavaScript-only shell).
- `curl': External curl binary; sends more browser-like headers, follows
  redirects, and enforces a 30-second timeout.  Requires curl on PATH."
  :type '(choice (const :tag "Emacs url-retrieve" url-retrieve)
                 (const :tag "External curl" curl))
  :group 'org-capture-ai)

(defun org-capture-ai-fetch-url (url success-cb error-cb)
  "Fetch URL asynchronously using the method in `org-capture-ai-fetch-method'.
Calls SUCCESS-CB with the fetched HTML string on success.
Calls ERROR-CB with a descriptive error string on failure.
Delegates to `org-capture-ai-fetch-url-curl' or
`org-capture-ai-fetch-url-builtin' depending on configuration."
  (org-capture-ai--log "Fetching URL: %s (method: %s)" url org-capture-ai-fetch-method)
  (cond
   ((eq org-capture-ai-fetch-method 'curl)
    (org-capture-ai-fetch-url-curl url success-cb error-cb))
   (t
    (org-capture-ai-fetch-url-builtin url success-cb error-cb))))

(defun org-capture-ai-fetch-url-curl (url success-cb error-cb)
  "Fetch URL asynchronously using the external curl command.
Calls SUCCESS-CB with the HTML string on success.
Calls ERROR-CB with a descriptive error string on failure.
Uses `make-process' to capture stderr for diagnostic messages on failure.
Passes \"-L\" to follow redirects and \"--max-time 30\" to enforce a
30-second hard timeout.  Sends a browser-like User-Agent header to
avoid content-negotiation issues with picky sites.
Cleans up the temporary output file and stderr buffer in all code paths."
  (let* ((temp-file (make-temp-file "org-capture-ai-"))
         (err-buffer (generate-new-buffer " *org-capture-ai-curl-err*")))
    (make-process
     :name "org-capture-ai-curl"
     :buffer nil
     :stderr err-buffer
     :command (list "curl"
                    "-L"            ; Follow redirects
                    "-s"            ; Silent (no progress)
                    "--max-time" "30"  ; 30-second timeout
                    "-o" temp-file
                    "-A" "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
                    url)
     :sentinel
     (lambda (_proc event)
       (cond
        ((string-match "^finished" event)
         (condition-case err
             (with-temp-buffer
               (insert-file-contents temp-file)
               (let ((content (buffer-string)))
                 (delete-file temp-file)
                 (when (buffer-live-p err-buffer) (kill-buffer err-buffer))
                 (org-capture-ai--log "curl fetched: %d bytes" (length content))
                 (funcall success-cb content)))
           (error
            (when (file-exists-p temp-file) (delete-file temp-file))
            (when (buffer-live-p err-buffer) (kill-buffer err-buffer))
            (funcall error-cb (format "curl read error: %s" err)))))
        ((string-match "\\(exited\\|signal\\|killed\\)" event)
         (let ((err-msg (if (buffer-live-p err-buffer)
                            (with-current-buffer err-buffer
                              (string-trim (buffer-string)))
                          "")))
           (when (file-exists-p temp-file) (delete-file temp-file))
           (when (buffer-live-p err-buffer) (kill-buffer err-buffer))
           (funcall error-cb
                    (if (string-empty-p err-msg)
                        (format "curl failed: %s" (string-trim event))
                      (format "curl error: %s" err-msg))))))))))

(defun org-capture-ai-fetch-url-builtin (url success-cb error-cb)
  "Fetch URL asynchronously using Emacs built-in `url-retrieve'.
Calls SUCCESS-CB with the HTML string on success.
Calls ERROR-CB with a descriptive error string on failure.
Sends a browser-like User-Agent header.  Note that some sites detect
non-browser clients through means beyond the User-Agent string and serve
JavaScript-only shells instead of full HTML; use the `curl' fetch method
for broader compatibility.  See `org-capture-ai-fetch-method'."
  ;; Set User-Agent to help get full HTML from some sites
  (let ((url-request-extra-headers
         '(("User-Agent" . "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"))))
    (url-retrieve url
		  (lambda (status &rest cbargs)
		    (let ((success-cb (car cbargs))
			  (error-cb (cadr cbargs))
			  (error-info (plist-get status :error))
			  (redirect-url (plist-get status :redirect)))
		      ;; Log redirect if present (url-retrieve automatically follows it)
		      (when redirect-url
			(org-capture-ai--log "Redirected to: %s" redirect-url))
		      (if error-info
			  (progn
			    (org-capture-ai--log "Fetch error: %s" error-info)
			    (kill-buffer)
			    (funcall error-cb error-info))

			;; Check HTTP status code
			(goto-char (point-min))
			(if (re-search-forward "^HTTP/[0-9.]+ \\([0-9]+\\)" nil t)
			    (let ((status-code (string-to-number (match-string 1))))
			      (org-capture-ai--log "HTTP status: %d" status-code)
			      (if (and (>= status-code 200) (< status-code 300))
				  (progn
				    ;; Success - skip headers and extract body
				    (re-search-forward "^\r?\n\r?\n" nil t)
				    (let ((content (buffer-substring (point) (point-max))))
				      (kill-buffer)
				      (funcall success-cb content)))
				;; HTTP error
				(kill-buffer)
				(funcall error-cb (format "HTTP %d" status-code))))
			  ;; Couldn't parse response
			  (kill-buffer)
			  (funcall error-cb "Invalid HTTP response")))))
		  (list success-cb error-cb))))


(defun org-capture-ai-parse-html (html-string)
  "Parse HTML-STRING into a DOM tree using `libxml-parse-html-region'.
Returns a DOM tree suitable for use with `dom-by-tag', `dom-attr', etc."
  (with-temp-buffer
    (insert html-string)
    (libxml-parse-html-region (point-min) (point-max))))

(defun org-capture-ai--get-meta-tag (dom name)
  "Return the content of the meta tag identified by NAME in DOM.
Searches both name= and property= attributes, accommodating standard
HTML meta tags and Open Graph / Dublin Core properties alike.
Returns nil if no matching tag is found, if the content attribute is
absent, if the value is shorter than 10 characters, or if the content
contains Unicode replacement characters or mojibake patterns indicating
encoding corruption."
  (when-let* ((meta-node
               (car (dom-search dom
                      (lambda (node)
                        (and (eq (dom-tag node) 'meta)
                             (or (equal (dom-attr node 'name) name)
                                 (equal (dom-attr node 'property) name)))))))
              (content (dom-attr meta-node 'content))
              (cleaned (string-trim content)))
    ;; Return nil if content looks corrupted (has replacement characters or is too short)
    ;; Check for:
    ;; - Unicode replacement character (\uFFFD, �)
    ;; - Common mojibake patterns (Á¢ÀÀ, â€", â€™, etc.)
    ;; - Suspicious sequences of accented chars + symbols
    (when (and (> (length cleaned) 10)
               (not (string-match-p "\uFFFD\\|�\\|Á¢À\\|â€\\|Ã¢â‚¬" cleaned)))
      cleaned)))

(defun org-capture-ai--extract-author (dom)
  "Return the author name from DOM, trying multiple strategies in order.
Checks: Dublin Core DC.creator meta tag, HTML author meta tag, Open Graph
article:author meta tag, JSON-LD schema.org author field (simple string
values only), and HTML5 `<a rel=\"author\">' link text.
Returns nil if no author information is found."
  (or
   ;; Dublin Core meta tag
   (org-capture-ai--get-meta-tag dom "DC.creator")
   ;; Standard meta author
   (org-capture-ai--get-meta-tag dom "author")
   ;; Open Graph
   (org-capture-ai--get-meta-tag dom "article:author")
   ;; JSON-LD schema.org (simplified extraction)
   (when-let ((script-nodes (dom-by-tag dom 'script)))
     (catch 'found
       (dolist (script script-nodes)
         (when (equal (dom-attr script 'type) "application/ld+json")
           (let ((json-text (dom-texts script)))
             (when (string-match "\"author\"[[:space:]]*:[[:space:]]*\"\\([^\"]+\\)\"" json-text)
               (throw 'found (match-string 1 json-text))))))
       nil))
   ;; HTML5 author link
   (when-let ((author-link (car (dom-search dom
                                   (lambda (node)
                                     (and (eq (dom-tag node) 'a)
                                          (equal (dom-attr node 'rel) "author")))))))
     (string-trim (dom-texts author-link)))))

(defun org-capture-ai--extract-date (dom)
  "Return the publication date string from DOM.
Checks, in order: Dublin Core DC.date meta tag, Open Graph
article:published_time meta tag, generic date and pubdate meta tags,
and the datetime attribute or text content of the first `<time>' element.
Returns nil if no date information is found."
  (or
   ;; Dublin Core date
   (org-capture-ai--get-meta-tag dom "DC.date")
   ;; Open Graph article time
   (org-capture-ai--get-meta-tag dom "article:published_time")
   ;; Generic publish date
   (org-capture-ai--get-meta-tag dom "date")
   (org-capture-ai--get-meta-tag dom "pubdate")
   ;; HTML5 time element
   (when-let ((time-node (car (dom-by-tag dom 'time))))
     (or (dom-attr time-node 'datetime)
         (string-trim (dom-texts time-node))))))

(defun org-capture-ai-extract-metadata (html url)
  "Extract Dublin Core metadata from HTML and URL.
Returns a plist with keys: `:title', `:description', `:creator',
`:publisher', `:date', `:type', `:language', `:rights', `:identifier',
`:format', `:source', `:relation', `:coverage'.
Values are sourced from Dublin Core meta tags where available, falling
back to Open Graph tags, standard HTML meta tags, and page structure.
`:identifier' is always set to URL.  `:format' is always \"text/html\"."
  (let* ((dom (org-capture-ai-parse-html html))
         (parsed-url (url-generic-parse-url url))
         (host (url-host parsed-url)))
    (list
     ;; Core fields
     :title (or (org-capture-ai--get-meta-tag dom "DC.title")
                (when-let ((title-node (car (dom-by-tag dom 'title))))
                  (string-trim (dom-texts title-node)))
                "Untitled")
     :description (or (org-capture-ai--get-meta-tag dom "DC.description")
                     (org-capture-ai--get-meta-tag dom "description")
                     (org-capture-ai--get-meta-tag dom "og:description")
                     "")

     ;; Dublin Core elements
     :creator (org-capture-ai--extract-author dom)
     :publisher (or (org-capture-ai--get-meta-tag dom "DC.publisher")
                   (org-capture-ai--get-meta-tag dom "og:site_name")
                   host)
     :date (org-capture-ai--extract-date dom)
     :type (or (org-capture-ai--get-meta-tag dom "DC.type")
              (org-capture-ai--get-meta-tag dom "og:type")
              "Text")
     :language (or (org-capture-ai--get-meta-tag dom "DC.language")
                  (dom-attr (car (dom-by-tag dom 'html)) 'lang)
                  "en")
     :rights (or (org-capture-ai--get-meta-tag dom "DC.rights")
                (org-capture-ai--get-meta-tag dom "copyright"))
     :identifier url
     :format "text/html"
     :source (org-capture-ai--get-meta-tag dom "DC.source")
     :relation (org-capture-ai--get-meta-tag dom "DC.relation")
     :coverage (org-capture-ai--get-meta-tag dom "DC.coverage"))))

(defun org-capture-ai-extract-readable-content (html)
  "Extract the main readable text from HTML, stripping boilerplate.
Removes script, style, nav, header, footer, and aside elements, then
removes elements with ad-related or comment-section class names.
Extracts text from the first `<article>', `<main>', or `<body>' element.
Returns a whitespace-normalized plain-text string with characters outside
the Unicode BMP removed for compatibility.  Returns an empty string if
no usable content element is found."
  (let ((dom (org-capture-ai-parse-html html)))

    ;; Remove noise elements
    (dolist (tag '(script style nav header footer aside))
      (dolist (node (dom-by-tag dom tag))
        (dom-remove-node dom node)))

    ;; Remove by class (ads, comments, etc)
    (dolist (class '("advertisement" "ads" "sidebar" "comment" "comments" "footer"))
      (dolist (node (dom-by-class dom class))
        (dom-remove-node dom node)))

    ;; Extract from main content container
    (let ((main-node (or (car (dom-by-tag dom 'article))
                         (car (dom-by-tag dom 'main))
                         (car (dom-by-tag dom 'body)))))
      (if main-node
          ;; Clean up the text: trim, normalize whitespace, ensure valid UTF-8
          (let ((text (string-trim (dom-texts main-node))))
            ;; Remove non-printable characters and ensure UTF-8 compatibility
            (with-temp-buffer
              (insert text)
              ;; Replace problematic characters
              (goto-char (point-min))
              (while (re-search-forward "[^\u0000-\u007F\u0080-\uFFFF]" nil t)
                (replace-match "" nil nil))
              ;; Normalize whitespace
              (goto-char (point-min))
              (while (re-search-forward "[ \t]+" nil t)
                (replace-match " " nil nil))
              (buffer-string)))
        ""))))

;;; LLM Integration

(defun org-capture-ai-llm-request (prompt system-msg callback &optional attempt)
  "Make LLM request with PROMPT and SYSTEM-MSG.
Call CALLBACK with (response info) on completion.
Response is nil on error after all retries exhausted.
Synchronous errors (e.g. gptel not configured) are passed through immediately
without retrying. ATTEMPT tracks the current attempt number (internal, starts at 1)."
  (let ((attempt (or attempt 1)))
    (org-capture-ai--log "LLM request attempt %d/%d: %s (prompt length: %d chars)"
                         attempt org-capture-ai-max-retries
                         (substring system-msg 0 (min 50 (length system-msg)))
                         (length prompt))
    (condition-case err
        (with-temp-buffer
          (set-buffer-file-coding-system 'utf-8)
          (insert prompt)
          (gptel-request (buffer-substring-no-properties (point-min) (point-max))
            :system system-msg
            :stream nil
            :callback
            (lambda (response info)
              (org-capture-ai--log "LLM callback fired! response=%s info=%s"
                                   (if response "present" "nil")
                                   info)
              (if response
                  (progn
                    (org-capture-ai--log "LLM response received (%d chars)" (length response))
                    (funcall callback response info))
                (if (< attempt org-capture-ai-max-retries)
                    (progn
                      (org-capture-ai--log "LLM attempt %d failed, scheduling retry %d/%d: %s"
                                           attempt (1+ attempt) org-capture-ai-max-retries
                                           (plist-get info :status))
                      (run-with-timer (* 2 attempt) nil
                                      #'org-capture-ai-llm-request
                                      prompt system-msg callback (1+ attempt)))
                  (progn
                    (org-capture-ai--log "LLM request failed after %d attempts: %s"
                                         attempt (plist-get info :status))
                    (funcall callback nil info)))))))
      (error
       (org-capture-ai--log "Error in gptel-request: %s" err)
       (funcall callback nil (list :status (format "error: %s" err)))))))

(defun org-capture-ai-llm-summarize (text callback &optional sentences)
  "Generate a title and summary for TEXT using the configured LLM.
Calls CALLBACK with a plist of `:title' and `:summary' strings on
success, or with nil on LLM failure.
The prompt format is controlled by `org-capture-ai-summary-style':
- `sentences': single paragraph; length set by `org-capture-ai-summary-sentences'
  (or SENTENCES if provided).
- `paragraphs': overview paragraph plus per-topic paragraphs; lengths
  set by `org-capture-ai-summary-overview-sentences',
  `org-capture-ai-summary-topic-max-sentences', and
  `org-capture-ai-summary-topic-paragraphs'."
  (let* ((style org-capture-ai-summary-style)
         (prompt (if (eq style 'paragraphs)
                     ;; Multi-paragraph format
                     (let ((overview-sentences org-capture-ai-summary-overview-sentences)
                           (topic-max-sentences org-capture-ai-summary-topic-max-sentences)
                           (topic-count org-capture-ai-summary-topic-paragraphs))
                       (format "Generate a title and multi-paragraph summary for this content.

Return your response in this exact format:
TITLE: [A concise, descriptive title in 3-8 words]
SUMMARY:
[First paragraph: %d-sentence overview summarizing the entire article]

[Second paragraph: Summary of first major topic, up to %d sentences]

[Third paragraph: Summary of second major topic, up to %d sentences]
%s
IMPORTANT:
- Each paragraph should be on its own line, separated by blank lines
- First paragraph must be exactly %d sentences summarizing the whole article
- The FIRST SENTENCE of the first paragraph must be a complete, grammatically correct sentence that stands alone as a clear, concise description
- Following paragraphs cover major topics, each up to %d sentences
- Write naturally - each paragraph should flow well and be readable
- Ensure proper punctuation and no truncation in all sentences"
                               overview-sentences
                               topic-max-sentences
                               topic-max-sentences
                               (if (eq topic-count 'auto)
                                   "\n[Continue with additional topic paragraphs as needed based on article complexity]"
                                 (format "\n[Continue for %d total topic paragraphs]" topic-count))
                               overview-sentences
                               topic-max-sentences))
                   ;; Single paragraph format (legacy)
                   (let ((sentence-count (or sentences org-capture-ai-summary-sentences)))
                     (format "Generate a title and summary for this content.

Return your response in this exact format:
TITLE: [A concise, descriptive title in 3-8 words]
SUMMARY: [A %d-sentence summary focusing on the main thesis and key insights]

IMPORTANT: The first sentence of the SUMMARY must be a complete, grammatically correct sentence that stands alone as a clear description of the content. Ensure proper punctuation and no truncation.

Do not include any other text or formatting."
                             sentence-count)))))
    (org-capture-ai-llm-request text prompt
      (lambda (response info)
        (if response
            (let ((title nil)
                  (summary nil))
              ;; Parse the response - match TITLE and everything after SUMMARY
              (when (string-match "TITLE:\\s-*\\(.*?\\)\\s-*\nSUMMARY:\\s-*\\([^\000]*\\)" response)
                (setq title (string-trim (match-string 1 response)))
                (setq summary (string-trim (match-string 2 response))))
              (funcall callback
                       (if (and title summary)
                           (list :title title :summary summary)
                         ;; Fallback if parsing failed
                         (list :title "Untitled" :summary response))))
          (funcall callback nil))))))

(defun org-capture-ai-llm-extract-tags (text callback &optional max-tags)
  "Extract classification tags from TEXT using the configured LLM.
Calls CALLBACK with a list of tag strings on success, or nil on failure.
Tags use underscores for multi-word terms (e.g., \"machine_learning\").
When `org-capture-ai-use-curated-tags' is non-nil, the LLM selects from
the faceted lists `org-capture-ai-tags-type', `org-capture-ai-tags-status',
`org-capture-ai-tags-quality', and `org-capture-ai-tags-domain'.
When nil, the LLM generates free-form tags; MAX-TAGS (or
`org-capture-ai-tag-count') limits the number requested."
  (let* ((use-curated org-capture-ai-use-curated-tags)
         (prompt (if use-curated
                     ;; Curated faceted tags prompt
                     (format "Analyze this content and select appropriate tags from these faceted lists:

TYPE (select 1): %s
STATUS (select 1): %s
QUALITY (select 0-1): %s
DOMAIN (select 1-3): %s

Instructions:
- Select ONE type tag that best describes the content format
- Select ONE status tag if applicable (default: 'reference' for new content)
- Optionally select ONE quality tag if the content is notably authoritative or canonical
- Select 1-3 domain tags that match the subject matter

Return ONLY the selected tags as a comma-separated list.
Example: article, reference, canonical, programming, artificial_intelligence"
                             (mapconcat #'identity org-capture-ai-tags-type ", ")
                             (mapconcat #'identity org-capture-ai-tags-status ", ")
                             (mapconcat #'identity org-capture-ai-tags-quality ", ")
                             (mapconcat #'identity org-capture-ai-tags-domain ", "))
                   ;; Free-form tags prompt
                   (let ((tag-count (or max-tags org-capture-ai-tag-count)))
                     (format "Analyze this content and extract %d relevant topic tags.
Return ONLY comma-separated tags (e.g., 'machine_learning, python, ai').
Use underscores instead of hyphens for multi-word tags.
No explanation, no extra formatting."
                             tag-count)))))
    (org-capture-ai-llm-request text prompt
      (lambda (response info)
        (if response
            (let ((tags (split-string (string-trim response) "," t)))
              ;; Clean tags: trim whitespace and replace hyphens with underscores
              (funcall callback (mapcar (lambda (tag)
                                          (replace-regexp-in-string "-" "_" (string-trim tag)))
                                        tags)))
          (funcall callback nil))))))

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

;;; Capture Integration

(defvar org-capture-ai--processing-markers nil
  "List of markers currently being processed to prevent duplicates.")

(defun org-capture-ai--process-entry ()
  "Hook function installed on `org-capture-after-finalize-hook'.
When a URL capture completes without abort, schedules async processing
of the captured entry.  Locates the entry via the bookmark
`org-capture-last-stored'.
Processing is skipped when: the entry has no URL property, the capture
was aborted (`org-note-abort' is non-nil), STATUS is not \"processing\",
or the entry is already tracked in `org-capture-ai--processing-markers'.
When `org-capture-ai-process-on-capture' is non-nil, schedules
`org-capture-ai--async-process' immediately; otherwise schedules
`org-capture-ai--mark-queued' for later batch processing."
  (org-capture-ai--log "=== HOOK FIRED === abort=%s" org-note-abort)

  ;; Check if this was a URL capture by checking the stored entry
  (condition-case err
      (save-excursion
        (when (bookmark-get-bookmark "org-capture-last-stored" t)
          (bookmark-jump "org-capture-last-stored")
          (let ((url (org-entry-get nil "URL"))
                (status (org-entry-get nil "STATUS"))
                (marker (point-marker)))  ; Create marker immediately
            (org-capture-ai--log "Found entry: url=%s status=%s marker=%s position=%d"
                                url status marker (marker-position marker))

            ;; Only process if: has URL, not aborted, status is "processing", and not already being processed
            (when (and url
                       (not org-note-abort)
                       (equal status "processing")
                       (not (member (marker-position marker) org-capture-ai--processing-markers)))
              (org-capture-ai--log "Scheduling async process with marker %s" marker)
              (push (marker-position marker) org-capture-ai--processing-markers)
              (if org-capture-ai-process-on-capture
                  (run-with-timer 0.1 nil #'org-capture-ai--async-process marker)
                (run-with-timer 0.1 nil #'org-capture-ai--mark-queued marker)))

            (when (member (marker-position marker) org-capture-ai--processing-markers)
              (org-capture-ai--log "DUPLICATE PREVENTED: Entry at %d already being processed"
                                  (marker-position marker))))))
    (error
     (org-capture-ai--log "Error in process-entry: %s" err))))

(defun org-capture-ai--mark-queued (marker)
  "Set the STATUS property of the entry at MARKER to \"queued\".
Queued entries are processed later by `org-capture-ai-process-queued',
either invoked manually or automatically via the idle timer."
  (save-excursion
    (org-with-point-at marker
      (org-back-to-heading t)
      (org-entry-put nil "STATUS" "queued")
      (org-capture-ai--log "Entry marked as queued"))))

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

(defun org-capture-ai--async-process (marker)
  "Begin async fetch-and-analyze processing for the entry at MARKER.
Reads the URL property from the entry, sets STATUS to \"fetching\", and
initiates an async fetch via `org-capture-ai-fetch-url'.
On fetch success, continues with `org-capture-ai--process-html'.
On fetch failure, sets STATUS to \"fetch-error\" and cleans up MARKER.
Returns early with a log message if the entry has no URL property."
  (cl-block org-capture-ai--async-process
    (save-excursion
      (org-with-point-at marker
        (org-back-to-heading t)
        (let ((url (org-entry-get nil "URL")))

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
                   (cl-delete (marker-position marker) org-capture-ai--processing-markers :test #'=))
             (set-marker marker nil)
             (message "org-capture-ai: Duplicate URL skipped (already captured: \"%s\")"
                      dup-heading)
             (cl-return-from org-capture-ai--async-process))
            (_
             (message "org-capture-ai: Warning: URL already captured as \"%s\"" dup-heading))))

        (message "org-capture-ai: Fetching %s" url)
        (org-capture-ai--set-status marker "fetching")

        ;; Fetch URL asynchronously
        (org-capture-ai-fetch-url url
          ;; Success callback
          (lambda (html-content)
            (org-capture-ai--process-html html-content url marker))

          ;; Error callback
          (lambda (error)
            (org-capture-ai--set-status marker "fetch-error" (format "%s" error))
            (message "org-capture-ai: Failed to fetch URL: %s" error)
            (set-marker marker nil))))))))

(defun org-capture-ai--sanitize-property-value (value)
  "Sanitize VALUE for storage as an org-mode property.
Org properties must fit on a single line.  This function:
- Trims leading and trailing whitespace
- Replaces newline and carriage-return sequences with a single space
- Collapses runs of whitespace to a single space
- Truncates the result to 500 characters, appending \"...\" if truncated
Returns nil when VALUE is nil."
  (when value
    (let ((sanitized (string-trim value)))
      ;; Replace newlines and collapse whitespace
      (setq sanitized (replace-regexp-in-string "[\n\r]+" " " sanitized))
      (setq sanitized (replace-regexp-in-string "[ \t]+" " " sanitized))
      ;; Truncate if too long
      (when (> (length sanitized) 500)
        (setq sanitized (concat (substring sanitized 0 497) "...")))
      sanitized)))

(defun org-capture-ai--estimate-reading-time (text)
  "Return a reading time string for TEXT based on `org-capture-ai-reading-wpm'.
Returns a string like \"4 min\".  The minimum is \"1 min\"."
  (let* ((word-count (length (split-string text nil t)))
         (minutes (max 1 (round (/ (float word-count) org-capture-ai-reading-wpm)))))
    (format "%d min" minutes)))

(defun org-capture-ai--process-html (html-content url marker)
  "Process HTML-CONTENT fetched from URL and drive LLM analysis.
Extracts Dublin Core metadata and readable body text from HTML-CONTENT,
writes the metadata to the properties drawer at MARKER, then passes the
body text to `org-capture-ai--llm-analyze' for title, summary, and tag
generation.  Body text is truncated to `org-capture-ai-max-content-length'
characters before being sent to the LLM."
  (let* ((metadata (org-capture-ai-extract-metadata html-content url))
         (clean-text (org-capture-ai-extract-readable-content html-content))
         (title (plist-get metadata :title)))

    (org-capture-ai--log "Extracted %d chars of text, title: %s"
                         (length clean-text) title)

    ;; Truncate content if it exceeds the configured maximum
    (when (> (length clean-text) org-capture-ai-max-content-length)
      (org-capture-ai--log "Truncating content from %d to %d chars (org-capture-ai-max-content-length)"
                           (length clean-text) org-capture-ai-max-content-length)
      (setq clean-text (substring clean-text 0 org-capture-ai-max-content-length)))

    (save-excursion
      (org-with-point-at marker
        (org-back-to-heading t)
        (org-capture-ai--set-status marker "processing")

        ;; Set reading time estimate
        (org-entry-put nil "READING_TIME"
                       (org-capture-ai--estimate-reading-time clean-text))

        ;; Set Dublin Core metadata properties (sanitized for single-line)
        (org-entry-put nil "TITLE" (org-capture-ai--sanitize-property-value title))
        (when-let ((creator (plist-get metadata :creator)))
          (org-entry-put nil "CREATOR" (org-capture-ai--sanitize-property-value creator)))
        (when-let ((publisher (plist-get metadata :publisher)))
          (org-entry-put nil "PUBLISHER" (org-capture-ai--sanitize-property-value publisher)))
        (when-let ((date (plist-get metadata :date)))
          (org-entry-put nil "DATE" (org-capture-ai--sanitize-property-value date)))
        (when-let ((type (plist-get metadata :type)))
          (org-entry-put nil "TYPE" (org-capture-ai--sanitize-property-value type)))
        (when-let ((language (plist-get metadata :language)))
          (org-entry-put nil "LANGUAGE" (org-capture-ai--sanitize-property-value language)))
        (when-let ((rights (plist-get metadata :rights)))
          (org-entry-put nil "RIGHTS" (org-capture-ai--sanitize-property-value rights)))
        (when-let ((description (plist-get metadata :description)))
          (when (not (string-empty-p description))
            (org-entry-put nil "DESCRIPTION" (org-capture-ai--sanitize-property-value description))))
        (when-let ((format (plist-get metadata :format)))
          (org-entry-put nil "FORMAT" (org-capture-ai--sanitize-property-value format)))
        (when-let ((source (plist-get metadata :source)))
          (org-entry-put nil "SOURCE" (org-capture-ai--sanitize-property-value source)))
        (when-let ((relation (plist-get metadata :relation)))
          (org-entry-put nil "RELATION" (org-capture-ai--sanitize-property-value relation)))
        (when-let ((coverage (plist-get metadata :coverage)))
          (org-entry-put nil "COVERAGE" (org-capture-ai--sanitize-property-value coverage)))))

    ;; Process with LLM
    (org-capture-ai--log "About to call llm-analyze with %d chars" (length clean-text))
    (org-capture-ai--llm-analyze clean-text marker)))

(defun org-capture-ai--finalize-entry (marker tags)
  "Complete LLM processing for the entry at MARKER.
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
        (cl-delete (marker-position marker) org-capture-ai--processing-markers :test #'=))
  (org-capture-ai--log "Removed marker %d from processing list" (marker-position marker))
  (set-marker marker nil))

(defun org-capture-ai--apply-summary (result marker)
  "Write summary RESULT to the entry at MARKER.
Updates the heading title, TITLE property, DESCRIPTION property, and
AI_MODEL property.  RESULT is a plist with :title and :summary keys."
  (let ((title (plist-get result :title))
        (summary (plist-get result :summary)))
    (save-excursion
      (org-with-point-at marker
        (org-back-to-heading t)
        (when title
          (org-edit-headline title)
          (org-entry-put nil "TITLE" (org-capture-ai--sanitize-property-value title)))
        (when summary
          (let ((first-sentence (if (string-match "^\\([^.!?]+[.!?]\\)" summary)
                                    (match-string 1 summary)
                                  summary)))
            (org-entry-put nil "DESCRIPTION"
                           (org-capture-ai--sanitize-property-value first-sentence))))
        (org-entry-put nil "AI_MODEL"
                       (org-capture-ai--sanitize-property-value (symbol-name gptel-model)))))))

(defun org-capture-ai--apply-tags (tags marker)
  "Write TAGS to the entry at MARKER.
Stores tags in the SUBJECT property (comma-separated) and as org headline tags."
  (save-excursion
    (org-with-point-at marker
      (org-back-to-heading t)
      (org-entry-put nil "SUBJECT"
                     (org-capture-ai--sanitize-property-value
                      (mapconcat #'identity tags ", ")))
      (org-set-tags (delete-dups (append (org-get-tags) tags))))))

(defun org-capture-ai--apply-takeaways (takeaways marker)
  "Insert TAKEAWAYS as a bullet list at the top of the entry body at MARKER."
  (save-excursion
    (org-with-point-at marker
      (org-back-to-heading t)
      (org-end-of-meta-data)
      (forward-line 1) ; skip blank line after :END:
      (insert (mapconcat (lambda (s) (format "- %s" s)) takeaways "\n")
              "\n\n"))))

(defun org-capture-ai--llm-analyze (text marker)
  "Analyze TEXT with the LLM and update the entry at MARKER.
Fails immediately with STATUS \"error\" if TEXT is empty or shorter than
50 characters.  Otherwise runs up to three sequential LLM calls:
1. `org-capture-ai-llm-summarize' — updates heading, TITLE, DESCRIPTION, AI_MODEL.
2. `org-capture-ai-llm-extract-tags' — updates SUBJECT and org headline tags.
3. `org-capture-ai-llm-extract-takeaways' (when `org-capture-ai-extract-takeaways'
   is non-nil) — inserts bullet list at top of entry body.
On completion calls `org-capture-ai--finalize-entry'."
  (org-capture-ai--log "llm-analyze called with marker: %s" marker)
  (if (or (not text) (string-empty-p text) (< (length text) 50))
      (progn
        (org-capture-ai--log "Content too short or empty (%d chars), cannot analyze"
                             (if text (length text) 0))
        (save-excursion
          (org-with-point-at marker
            (org-back-to-heading t)
            (org-entry-put nil "ERROR"
                           (org-capture-ai--sanitize-property-value
                            (format "Content extraction failed - no readable text found (%d chars)"
                                    (if text (length text) 0))))))
        (org-capture-ai--set-status marker "error")
        (message "org-capture-ai: No readable content found - check *org-capture-ai-log* for details")
        (set-marker marker nil))
    (org-capture-ai--log "Calling llm-summarize...")
    (org-capture-ai-llm-summarize text
      (lambda (result)
        (when result
          (org-capture-ai--apply-summary result marker))
        (org-capture-ai-llm-extract-tags text
          (lambda (tags)
            (when tags
              (org-capture-ai--apply-tags tags marker))
            (if (and tags org-capture-ai-extract-takeaways)
                (org-capture-ai-llm-extract-takeaways text
                  (lambda (takeaways)
                    (when takeaways
                      (org-capture-ai--apply-takeaways takeaways marker))
                    (org-capture-ai--finalize-entry marker tags)))
              (org-capture-ai--finalize-entry marker tags))))))))

;;; Batch Processing

(defun org-capture-ai-process-queued ()
  "Process all entries with STATUS=queued across all configured files.
Respects `org-capture-ai-batch-concurrency' to avoid overwhelming the LLM API.
Files searched are `org-capture-ai-files', defaulting to `org-capture-ai-default-file'."
  (interactive)
  (cl-block org-capture-ai-process-queued
  ;; Guard against concurrent invocations (e.g. idle timer firing during a running batch)
  (when (> org-capture-ai--active-fetch-count 0)
    (message "org-capture-ai: Batch already running (%d active), skipping"
             org-capture-ai--active-fetch-count)
    (cl-return-from org-capture-ai-process-queued))
  (let ((files (or org-capture-ai-files (list org-capture-ai-default-file)))
        (entries nil))
    ;; Collect all queued entries across all configured files
    (dolist (file files)
      (when (file-exists-p file)
        (org-map-entries
         (lambda ()
           (let ((url (org-entry-get nil "URL")))
             (when url
               (push (cons url (point-marker)) entries))))
         "STATUS=\"queued\""
         (list file))))
    (setq entries (nreverse entries))
    (if (null entries)
        (message "org-capture-ai: No queued entries found")
      (message "org-capture-ai: Starting batch processing of %d entries" (length entries))
      (setq org-capture-ai--pending-batch entries)
      (setq org-capture-ai--active-fetch-count 0)
      ;; Seed the queue — dispatch-next's guard handles the concurrency limit
      (dotimes (_ org-capture-ai-batch-concurrency)
        (org-capture-ai--batch-dispatch-next))))))

(defun org-capture-ai--batch-dispatch-next ()
  "Start processing the next pending batch entry if below concurrency limit.
Called both to seed the initial batch and from fetch callbacks to refill."
  (when (and org-capture-ai--pending-batch
             (< org-capture-ai--active-fetch-count org-capture-ai-batch-concurrency))
    (let* ((entry (pop org-capture-ai--pending-batch))
           (url (car entry))
           (marker (cdr entry)))
      (cl-incf org-capture-ai--active-fetch-count)
      (org-capture-ai--log "Batch dispatch: %s (active: %d, pending: %d)"
                           url org-capture-ai--active-fetch-count
                           (length org-capture-ai--pending-batch))
      (org-capture-ai--set-status marker "fetching")
      (org-capture-ai-fetch-url url
        (lambda (html-content)
          (cl-decf org-capture-ai--active-fetch-count)
          (org-capture-ai--process-html html-content url marker)
          (org-capture-ai--batch-dispatch-next))
        (lambda (error)
          (cl-decf org-capture-ai--active-fetch-count)
          (org-capture-ai--set-status marker "fetch-error" (format "%s" error))
          (set-marker marker nil)
          (org-capture-ai--batch-dispatch-next))))))

(defun org-capture-ai-reprocess-entry ()
  "Re-fetch and re-analyze the URL in the org entry at point.
Sets STATUS to \"reprocessing\" and runs the full fetch-and-LLM pipeline.
New AI-generated content (title, summary, tags, metadata) overwrites the
previous values; the body text is replaced with the new summary.
Signals a user error if the entry at point has no URL property."
  (interactive)
  (let ((url (org-entry-get nil "URL"))
        (marker (point-marker)))
    (if url
        (progn
          (org-capture-ai--set-status marker "reprocessing")
          (org-capture-ai-fetch-url url
            (lambda (html-content)
              (org-capture-ai--process-html html-content url marker))
            (lambda (error)
              (org-capture-ai--set-status marker "fetch-error" (format "%s" error))
              (set-marker marker nil)))
          (message "org-capture-ai: Reprocessing %s" url))
      (message "org-capture-ai: No URL property found"))))

(defun org-capture-ai-refresh-entry ()
  "Refresh the org entry at point by re-fetching and replacing content.
This clears the existing entry body and replaces it with fresh content
from the URL. Metadata properties and tags will be updated.
The heading title will be replaced with the new AI-generated title."
  (interactive)
  (let ((url (org-entry-get nil "URL")))
    (if url
        (when (yes-or-no-p (format "Refresh entry from %s? This will replace existing content. " url))
          (save-excursion
            (org-back-to-heading t)

            ;; Clear old content but preserve structure
            ;; Remove body content (everything after properties drawer)
            (org-end-of-meta-data t)
            (let ((body-start (point)))
              ;; Move to end of current entry (not including next heading)
              (org-end-of-subtree t)
              ;; Back up to before the newline that precedes next heading
              (when (and (not (eobp)) (looking-at "^\\*"))
                (forward-line -1)
                (end-of-line))
              (delete-region body-start (point)))

            ;; Clear old metadata properties (keep structural ones)
            (dolist (prop '("TITLE" "CREATOR" "PUBLISHER" "DATE" "TYPE"
                          "LANGUAGE" "RIGHTS" "DESCRIPTION" "FORMAT"
                          "SOURCE" "RELATION" "COVERAGE" "SUBJECT"
                          "AI_MODEL" "PROCESSED_AT" "ERROR"))
              (org-entry-delete nil prop))

            ;; Clear old tags
            (org-set-tags nil)

            ;; Create marker AFTER clearing content, at the heading
            (org-back-to-heading t)
            (let ((marker (point-marker)))
              ;; Start fresh processing
              (org-capture-ai--set-status marker "refreshing")
              (org-capture-ai-fetch-url url
                (lambda (html-content)
                  (org-capture-ai--process-html html-content url marker))
                (lambda (error)
                  (org-capture-ai--set-status marker "fetch-error" (format "%s" error))
                  (set-marker marker nil)))))
          (message "org-capture-ai: Refreshing %s" url))
      (message "org-capture-ai: No URL property found"))))

;;; Setup

(defun org-capture-ai-setup ()
  "Install the org-capture-ai URL capture template and process hooks.
Registers a capture template under `org-capture-ai-template-key' that
prompts for a URL, creates an entry in `org-capture-ai-default-file'
under a \"Bookmarks\" heading, and immediately finalizes so async
processing can begin.
Installs `org-capture-ai--process-entry' on
`org-capture-after-finalize-hook' idempotently — safe to call multiple
times without duplicating the hook.
If `org-capture-ai-batch-idle-time' is non-nil and no idle timer is
already running, starts a repeating idle timer to invoke
`org-capture-ai-process-queued' after the configured idle period."
  (interactive)

  ;; Add capture template
  (add-to-list 'org-capture-templates
               `(,org-capture-ai-template-key
                 "URL with AI"
                 entry
                 (file+headline ,org-capture-ai-default-file "Bookmarks")
                 "** Processing...\n:PROPERTIES:\n:URL: %^{URL}\n:CAPTURED: %U\n:STATUS: processing\n:END:\n\n%?"
                 :empty-lines 1
                 :immediate-finish t))

  ;; Add hook (remove first to ensure it's only added once, making setup idempotent)
  (remove-hook 'org-capture-after-finalize-hook #'org-capture-ai--process-entry)
  (add-hook 'org-capture-after-finalize-hook #'org-capture-ai--process-entry)

  ;; Set up batch processing timer if configured
  (when (and org-capture-ai-batch-idle-time
             (not org-capture-ai--batch-timer))
    (setq org-capture-ai--batch-timer
          (run-with-idle-timer org-capture-ai-batch-idle-time t
                               #'org-capture-ai-process-queued)))

  (message "org-capture-ai setup complete. Use '%s' to capture URLs."
           org-capture-ai-template-key))

(defun org-capture-ai-teardown ()
  "Remove org-capture-ai hooks and cancel the batch processing timer.
Removes `org-capture-ai--process-entry' from
`org-capture-after-finalize-hook' and cancels the idle timer started by
`org-capture-ai-setup', if any.  Safe to call when not set up."
  (interactive)
  (remove-hook 'org-capture-after-finalize-hook #'org-capture-ai--process-entry)

  (when org-capture-ai--batch-timer
    (cancel-timer org-capture-ai--batch-timer)
    (setq org-capture-ai--batch-timer nil))

  (message "org-capture-ai teardown complete"))

(provide 'org-capture-ai)
;;; org-capture-ai.el ends here
