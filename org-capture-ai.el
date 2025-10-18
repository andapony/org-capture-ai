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
  "Default file for AI-enhanced URL captures."
  :type 'file
  :group 'org-capture-ai)

(defcustom org-capture-ai-template-key "u"
  "Default capture template key for URL capture."
  :type 'string
  :group 'org-capture-ai)

(defcustom org-capture-ai-summary-sentences 3
  "Number of sentences for AI-generated summaries.
Only used when `org-capture-ai-summary-style' is 'sentences."
  :type 'integer
  :group 'org-capture-ai)

(defcustom org-capture-ai-summary-style 'sentences
  "Style of AI-generated summaries.
- 'sentences: Single paragraph with N sentences (default)
- 'paragraphs: Multi-paragraph with overview + topic sections"
  :type '(choice (const :tag "Single paragraph (sentences)" sentences)
                 (const :tag "Multi-paragraph (overview + topics)" paragraphs))
  :group 'org-capture-ai)

(defcustom org-capture-ai-summary-overview-sentences 3
  "Number of sentences in the overview paragraph.
Used when `org-capture-ai-summary-style' is 'paragraphs."
  :type 'integer
  :group 'org-capture-ai)

(defcustom org-capture-ai-summary-topic-paragraphs 'auto
  "Number of topic paragraphs to generate.
Used when `org-capture-ai-summary-style' is 'paragraphs.
- 'auto: Let the LLM decide based on article content
- Integer: Request specific number of topic paragraphs"
  :type '(choice (const :tag "Auto (LLM decides)" auto)
                 (integer :tag "Fixed number"))
  :group 'org-capture-ai)

(defcustom org-capture-ai-summary-topic-max-sentences 5
  "Maximum sentences per topic paragraph.
Used when `org-capture-ai-summary-style' is 'paragraphs."
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
  "Maximum number of retry attempts for failed LLM requests."
  :type 'integer
  :group 'org-capture-ai)

(defcustom org-capture-ai-enable-logging t
  "Enable logging to *org-capture-ai-log* buffer."
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

;;; Internal Variables

(defvar org-capture-ai--batch-timer nil
  "Timer for batch processing queued entries.")

(defvar org-capture-ai--cache (make-hash-table :test 'equal)
  "Cache for LLM results keyed by content hash.")

;;; Logging

(defun org-capture-ai--log (format-string &rest args)
  "Log message to *org-capture-ai-log* buffer if logging is enabled.
FORMAT-STRING and ARGS are passed to `format'."
  (when org-capture-ai-enable-logging
    (with-current-buffer (get-buffer-create "*org-capture-ai-log*")
      (goto-char (point-max))
      (insert (format "[%s] %s\n"
                      (format-time-string "%Y-%m-%d %H:%M:%S")
                      (apply #'format format-string args))))))

;;; Status Management

(defun org-capture-ai--set-status (marker status &optional error-msg)
  "Set STATUS at MARKER with optional ERROR-MSG.
Auto-saves buffer on terminal states (completed, error, fetch-error)."
  (org-capture-ai--log "Setting status to %s at marker %s" status marker)
  (save-excursion
    (org-with-point-at marker
      (org-back-to-heading t)
      (org-entry-put nil "STATUS" status)
      (org-entry-put nil "UPDATED_AT" (format-time-string "[%Y-%m-%d %a %H:%M]"))
      (when error-msg
        (org-entry-put nil "ERROR" error-msg))
      ;; Auto-save on terminal states
      (when (member status '("completed" "error" "fetch-error"))
        (save-buffer)))))

;;; HTML Processing

(defun org-capture-ai-fetch-url (url success-callback error-callback &optional max-redirects)
  "Fetch URL asynchronously, following redirects.
Call SUCCESS-CALLBACK with HTML content on success.
Call ERROR-CALLBACK with error info on failure.
MAX-REDIRECTS limits redirect following (default 5)."
  (let ((max-redirects (or max-redirects 5)))
    (org-capture-ai--log "Fetching URL: %s (max redirects: %d)" url max-redirects)
    (url-retrieve url
      (lambda (status)
        (let ((error-info (plist-get status :error)))
          (if error-info
              (progn
                (org-capture-ai--log "Fetch error: %s" error-info)
                (kill-buffer)
                (funcall error-callback error-info))

            ;; Check HTTP status code
            (goto-char (point-min))
            (if (re-search-forward "^HTTP/[0-9.]+ \\([0-9]+\\)" nil t)
                (let ((status-code (string-to-number (match-string 1))))
                  (org-capture-ai--log "HTTP status: %d" status-code)
                  (cond
                   ;; Success - extract content
                   ((and (>= status-code 200) (< status-code 300))
                    (progn
                      ;; Success - skip headers and extract body
                      (re-search-forward "^\r?\n\r?\n" nil t)
                      (let ((content (buffer-substring (point) (point-max))))
                        (kill-buffer)
                        (funcall success-callback content))))

                   ;; Redirect - follow Location header
                   ((and (>= status-code 300) (< status-code 400))
                    (if (> max-redirects 0)
                        (progn
                          ;; Extract Location header
                          (goto-char (point-min))
                          (if (re-search-forward "^[Ll]ocation: \\(.*\\)$" nil t)
                              (let ((location (string-trim (match-string 1))))
                                (org-capture-ai--log "Following redirect to: %s" location)
                                (kill-buffer)
                                ;; Recursively fetch the redirect location
                                (org-capture-ai-fetch-url location success-callback error-callback (1- max-redirects)))
                            ;; No Location header found
                            (kill-buffer)
                            (funcall error-callback (format "HTTP %d without Location header" status-code))))
                      ;; Too many redirects
                      (kill-buffer)
                      (funcall error-callback "Too many redirects")))

                   ;; HTTP error (4xx, 5xx)
                   (t
                    (kill-buffer)
                    (funcall error-callback (format "HTTP %d" status-code)))))
              ;; Couldn't parse response
              (kill-buffer)
              (funcall error-callback "Invalid HTTP response")))))
      nil t))))

(defun org-capture-ai-parse-html (html-string)
  "Parse HTML-STRING and return DOM tree."
  (with-temp-buffer
    (insert html-string)
    (libxml-parse-html-region (point-min) (point-max))))

(defun org-capture-ai--get-meta-tag (dom name)
  "Get content attribute from meta tag with NAME in DOM.
Checks both name= and property= attributes.
Returns nil if content is empty or malformed."
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
  "Extract author/creator from DOM using multiple strategies."
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
  "Extract publication date from DOM."
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
  "Extract Dublin Core metadata from HTML string and URL.
Returns a plist with Dublin Core elements."
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
  "Extract main readable content from HTML, filtering noise."
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

(defun org-capture-ai-llm-request (prompt system-msg callback)
  "Make LLM request with PROMPT and SYSTEM-MSG.
Call CALLBACK with (response info) on completion.
Response is nil on error."
  (org-capture-ai--log "LLM request: %s (prompt length: %d chars)"
                       (substring system-msg 0 (min 50 (length system-msg)))
                       (length prompt))
  (condition-case err
      ;; Create a temporary buffer with UTF-8 encoding for gptel
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
                (org-capture-ai--log "LLM response received (%d chars)" (length response))
              (org-capture-ai--log "LLM request failed: %s" (plist-get info :status)))
            (funcall callback response info))))
    (error
     (org-capture-ai--log "Error in gptel-request: %s" err)
     (funcall callback nil (list :status (format "error: %s" err))))))

(defun org-capture-ai-llm-summarize (text callback &optional sentences)
  "Summarize TEXT using LLM.
Call CALLBACK with a plist containing :title and :summary.
Optional SENTENCES overrides `org-capture-ai-summary-sentences'.
Uses `org-capture-ai-summary-style' to determine format."
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
  "Extract tags from TEXT using LLM.
Call CALLBACK with list of tag strings.
Optional MAX-TAGS overrides `org-capture-ai-tag-count'.
Uses curated faceted tags if `org-capture-ai-use-curated-tags' is t."
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

(defun org-capture-ai-llm-retry (text system-msg marker callback max-attempts)
  "Retry LLM request up to MAX-ATTEMPTS times.
TEXT is the prompt, SYSTEM-MSG is the system message.
Update status at MARKER and call CALLBACK on success."
  (let ((attempts 0))
    (cl-labels ((try-request ()
                  (setq attempts (1+ attempts))
                  (org-capture-ai--log "LLM attempt %d/%d" attempts max-attempts)
                  (gptel-request text
                    :system system-msg
                    :stream nil
                    :callback
                    (lambda (response info)
                      (if response
                          (funcall callback response)
                        (if (< attempts max-attempts)
                            (progn
                              (org-capture-ai--log "Retry %d/%d after error" attempts max-attempts)
                              (run-with-timer 2 nil #'try-request))
                          (progn
                            (org-capture-ai--set-status marker "error"
                              (format "Failed after %d attempts: %s"
                                      max-attempts
                                      (plist-get info :status)))
                            (funcall callback nil))))))))
      (try-request))))

;;; Capture Integration

(defun org-capture-ai--process-entry ()
  "Process the last captured URL entry with AI."
  (org-capture-ai--log "Hook fired. abort=%s plist=%s"
                       org-note-abort
                       org-capture-plist)

  ;; Check if this was a URL capture by checking the stored entry
  (condition-case err
      (save-excursion
        (when (bookmark-get-bookmark "org-capture-last-stored" t)
          (bookmark-jump "org-capture-last-stored")
          (let ((url (org-entry-get nil "URL"))
                (marker (point-marker)))  ; Create marker immediately
            (org-capture-ai--log "Found URL property: %s url=%s marker=%s" url url marker)
            (when (and url (not org-note-abort))
              (org-capture-ai--log "Scheduling async process with marker %s" marker)
              (if org-capture-ai-process-on-capture
                  (run-with-timer 0.1 nil #'org-capture-ai--async-process marker)
                (run-with-timer 0.1 nil #'org-capture-ai--mark-queued marker))))))
    (error
     (org-capture-ai--log "Error in process-entry: %s" err))))

(defun org-capture-ai--mark-queued (marker)
  "Mark the entry at MARKER as queued."
  (save-excursion
    (org-with-point-at marker
      (org-back-to-heading t)
      (org-entry-put nil "STATUS" "queued")
      (org-capture-ai--log "Entry marked as queued"))))

(defun org-capture-ai--async-process (marker)
  "Fetch URL and process with LLM asynchronously using MARKER."
  (save-excursion
    (org-with-point-at marker
      (org-back-to-heading t)
      (let ((url (org-entry-get nil "URL")))

        (unless url
          (org-capture-ai--log "No URL property found")
          (message "org-capture-ai: No URL property found")
          (cl-return-from org-capture-ai--async-process))

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
            (set-marker marker nil)))))))

(defun org-capture-ai--process-html (html-content url marker)
  "Extract content from HTML-CONTENT and send to LLM.
URL is the source URL. Update entry at MARKER with results."
  (let* ((metadata (org-capture-ai-extract-metadata html-content url))
         (clean-text (org-capture-ai-extract-readable-content html-content))
         (title (plist-get metadata :title)))

    (org-capture-ai--log "Extracted %d chars of text, title: %s"
                         (length clean-text) title)

    (save-excursion
      (org-with-point-at marker
        (org-back-to-heading t)
        (org-capture-ai--set-status marker "processing")

        ;; Set Dublin Core metadata properties
        (org-entry-put nil "TITLE" title)
        (when-let ((creator (plist-get metadata :creator)))
          (org-entry-put nil "CREATOR" creator))
        (when-let ((publisher (plist-get metadata :publisher)))
          (org-entry-put nil "PUBLISHER" publisher))
        (when-let ((date (plist-get metadata :date)))
          (org-entry-put nil "DATE" date))
        (when-let ((type (plist-get metadata :type)))
          (org-entry-put nil "TYPE" type))
        (when-let ((language (plist-get metadata :language)))
          (org-entry-put nil "LANGUAGE" language))
        (when-let ((rights (plist-get metadata :rights)))
          (org-entry-put nil "RIGHTS" rights))
        (when-let ((description (plist-get metadata :description)))
          (when (not (string-empty-p description))
            (org-entry-put nil "DESCRIPTION" description)))
        (when-let ((format (plist-get metadata :format)))
          (org-entry-put nil "FORMAT" format))
        (when-let ((source (plist-get metadata :source)))
          (org-entry-put nil "SOURCE" source))
        (when-let ((relation (plist-get metadata :relation)))
          (org-entry-put nil "RELATION" relation))
        (when-let ((coverage (plist-get metadata :coverage)))
          (org-entry-put nil "COVERAGE" coverage))))

    ;; Process with LLM
    (org-capture-ai--log "About to call llm-analyze with %d chars" (length clean-text))
    (org-capture-ai--llm-analyze clean-text marker)))

(defun org-capture-ai--llm-analyze (text marker)
  "Analyze TEXT with LLM and update entry at MARKER."
  (org-capture-ai--log "llm-analyze called with marker: %s" marker)
  ;; First: Generate title and summary
  (org-capture-ai--log "Calling llm-summarize...")
  (org-capture-ai-llm-summarize text
    (lambda (result)
      (when result
        (let ((title (plist-get result :title))
              (summary (plist-get result :summary)))
          (save-excursion
            (org-with-point-at marker
              (org-back-to-heading t)

              ;; Update heading title and TITLE property
              (when title
                (let ((level (org-current-level)))
                  (beginning-of-line)
                  (looking-at org-complex-heading-regexp)
                  (replace-match (concat (make-string level ?*) " " title) nil nil nil 0))
                ;; Update TITLE property with AI-generated title
                (org-entry-put nil "TITLE" title))

              ;; Add summary to body
              (when summary
                ;; Move past properties but NOT past blank lines
                (org-end-of-meta-data)
                ;; Delete any existing blank lines
                (while (and (looking-at "^[ \t]*$") (not (eobp)))
                  (delete-region (point) (progn (forward-line 1) (point))))
                ;; Insert exactly one blank line, then the summary
                (insert "\n")
                ;; Insert summary and fill long lines
                (let ((start-pos (point)))
                  (insert summary "\n\n")
                  ;; Fill the inserted text to wrap long lines
                  (fill-region start-pos (- (point) 2) nil t))

                ;; Always set DESCRIPTION from AI summary (overwrites potentially corrupted HTML meta)
                ;; Use first sentence of summary for clean, complete description
                (let ((first-sentence (if (string-match "^\\([^.!?]+[.!?]\\)" summary)
                                          (match-string 1 summary)
                                        summary)))
                  (org-entry-put nil "DESCRIPTION" first-sentence)))

              (org-entry-put nil "AI_MODEL" (symbol-name gptel-model))))

          ;; Second: Extract tags
          (org-capture-ai-llm-extract-tags text
            (lambda (tags)
              (if tags
                  (save-excursion
                    (org-with-point-at marker
                      (org-back-to-heading t)

                      ;; Save as SUBJECT (Dublin Core)
                      (org-entry-put nil "SUBJECT" (mapconcat #'identity tags ", "))

                      ;; Also add as org tags (removing duplicates)
                      (org-set-tags (delete-dups (append (org-get-tags) tags)))

                      ;; Mark complete
                      (org-capture-ai--set-status marker "completed")
                      (org-entry-put nil "PROCESSED_AT"
                                     (format-time-string "[%Y-%m-%d %a %H:%M]"))

                      (message "org-capture-ai: Processing complete")))
                (org-capture-ai--set-status marker "error" "Tag extraction failed"))

              ;; Clean up marker
              (set-marker marker nil))))))))

;;; Batch Processing

(defun org-capture-ai-process-queued ()
  "Process all entries with STATUS=queued."
  (interactive)
  (let ((processed 0))
    (org-map-entries
     (lambda ()
       (let ((url (org-entry-get nil "URL"))
             (marker (point-marker)))
         (when url
           (setq processed (1+ processed))
           (org-capture-ai--log "Processing queued entry: %s" url)
           (org-capture-ai--set-status marker "fetching")

           ;; Fetch and process
           (org-capture-ai-fetch-url url
             (lambda (html-content)
               (org-capture-ai--process-html html-content url marker))
             (lambda (error)
               (org-capture-ai--set-status marker "fetch-error" (format "%s" error))
               (set-marker marker nil))))))
     "STATUS=\"queued\""
     (list org-capture-ai-default-file))
    (message "org-capture-ai: Started processing %d queued entries" processed)))

(defun org-capture-ai-reprocess-entry ()
  "Manually reprocess the org entry at point.
This adds new AI analysis to existing content without removing it."
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
  "Set up org-capture-ai with default configuration.
Adds capture template and hooks."
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

  ;; Add hook
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
  "Remove org-capture-ai hooks and timers."
  (interactive)
  (remove-hook 'org-capture-after-finalize-hook #'org-capture-ai--process-entry)

  (when org-capture-ai--batch-timer
    (cancel-timer org-capture-ai--batch-timer)
    (setq org-capture-ai--batch-timer nil))

  (message "org-capture-ai teardown complete"))

(provide 'org-capture-ai)
;;; org-capture-ai.el ends here
