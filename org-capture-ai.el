;;; org-capture-ai.el --- AI-enhanced URL capture for org-mode -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: AI-Generated
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (org "9.5") (gptel "0.7.0"))
;; Keywords: org, ai, capture, llm
;; URL: https://github.com/example/org-capture-ai

;;; Commentary:

;; org-capture-ai provides AI-enhanced URL capture for org-mode using LLMs.
;; It automatically fetches web content, extracts readable text, generates
;; summaries, and extracts tags using AI models via gptel.
;;
;; The workflow is: Capture → Finalize → Fetch URL → Call LLM → Update Properties
;; All processing happens asynchronously to avoid blocking Emacs.
;;
;; Usage:
;;   (require 'org-capture-ai)
;;   (org-capture-ai-setup)
;;
;; Then use the capture template (default key "u" for URL capture).

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

(defcustom org-capture-ai-default-file "~/org/bookmarks.org"
  "Default file for AI-enhanced URL captures."
  :type 'file
  :group 'org-capture-ai)

(defcustom org-capture-ai-template-key "u"
  "Default capture template key for URL capture."
  :type 'string
  :group 'org-capture-ai)

(defcustom org-capture-ai-summary-sentences 3
  "Number of sentences for AI-generated summaries."
  :type 'integer
  :group 'org-capture-ai)

(defcustom org-capture-ai-tag-count 5
  "Maximum number of tags to extract."
  :type 'integer
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
  "Set STATUS at MARKER with optional ERROR-MSG."
  (org-capture-ai--log "Setting status to %s at marker %s" status marker)
  (save-excursion
    (org-with-point-at marker
      (org-entry-put nil "STATUS" status)
      (org-entry-put nil "UPDATED_AT" (format-time-string "[%Y-%m-%d %a %H:%M]"))
      (when error-msg
        (org-entry-put nil "ERROR" error-msg)))))

;;; HTML Processing

(defun org-capture-ai-fetch-url (url success-callback error-callback)
  "Fetch URL asynchronously.
Call SUCCESS-CALLBACK with HTML content on success.
Call ERROR-CALLBACK with error info on failure."
  (org-capture-ai--log "Fetching URL: %s" url)
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
                (if (and (>= status-code 200) (< status-code 300))
                    (progn
                      ;; Success - skip headers and extract body
                      (re-search-forward "^\r?\n\r?\n" nil t)
                      (let ((content (buffer-substring (point) (point-max))))
                        (kill-buffer)
                        (funcall success-callback content)))
                  ;; HTTP error
                  (kill-buffer)
                  (funcall error-callback (format "HTTP %d" status-code))))
            ;; Couldn't parse response
            (kill-buffer)
            (funcall error-callback "Invalid HTTP response")))))))

(defun org-capture-ai-parse-html (html-string)
  "Parse HTML-STRING and return DOM tree."
  (with-temp-buffer
    (insert html-string)
    (libxml-parse-html-region (point-min) (point-max))))

(defun org-capture-ai-extract-metadata (html)
  "Extract title and description from HTML string."
  (let ((dom (org-capture-ai-parse-html html)))
    (list :title (or (when-let ((title-node (car (dom-by-tag dom 'title))))
                       (string-trim (dom-texts title-node)))
                     "Untitled")
          :description (or (when-let ((meta-node
                                      (car (dom-search dom
                                             (lambda (node)
                                               (and (eq (dom-tag node) 'meta)
                                                    (equal (dom-attr node 'name) "description")))))))
                            (dom-attr meta-node 'content))
                          ""))))

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
          (string-trim (dom-texts main-node))
        ""))))

;;; LLM Integration

(defun org-capture-ai-llm-request (prompt system-msg callback)
  "Make LLM request with PROMPT and SYSTEM-MSG.
Call CALLBACK with (response info) on completion.
Response is nil on error."
  (org-capture-ai--log "LLM request: %s" (substring system-msg 0 (min 50 (length system-msg))))
  (gptel-request prompt
    :system system-msg
    :stream nil
    :callback
    (lambda (response info)
      (if response
          (org-capture-ai--log "LLM response received (%d chars)" (length response))
        (org-capture-ai--log "LLM request failed: %s" (plist-get info :status)))
      (funcall callback response info))))

(defun org-capture-ai-llm-summarize (text callback &optional sentences)
  "Summarize TEXT using LLM.
Call CALLBACK with summary string.
Optional SENTENCES overrides `org-capture-ai-summary-sentences'."
  (let ((sentence-count (or sentences org-capture-ai-summary-sentences)))
    (org-capture-ai-llm-request text
      (format "Summarize this content in %d clear sentence%s. Focus on the main thesis and key insights."
              sentence-count
              (if (= sentence-count 1) "" "s"))
      (lambda (response info)
        (funcall callback
                 (if response
                     response
                   (format "[Summarization failed: %s]" (plist-get info :status))))))))

(defun org-capture-ai-llm-extract-tags (text callback &optional max-tags)
  "Extract tags from TEXT using LLM.
Call CALLBACK with list of tag strings.
Optional MAX-TAGS overrides `org-capture-ai-tag-count'."
  (let ((tag-count (or max-tags org-capture-ai-tag-count)))
    (org-capture-ai-llm-request text
      (format "Analyze this content and extract %d relevant topic tags.
Return ONLY comma-separated tags (e.g., 'machine-learning, python, ai').
No explanation, no extra formatting."
              tag-count)
      (lambda (response info)
        (if response
            (let ((tags (split-string (string-trim response) "," t)))
              (funcall callback (mapcar #'string-trim tags)))
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
  (when (and (not org-note-abort)
             (equal (plist-get org-capture-plist :key)
                    org-capture-ai-template-key))
    (if org-capture-ai-process-on-capture
        ;; Process immediately
        (run-with-timer 0.1 nil #'org-capture-ai--async-process)
      ;; Queue for later
      (run-with-timer 0.1 nil #'org-capture-ai--mark-queued))))

(defun org-capture-ai--mark-queued ()
  "Mark the last captured entry as queued."
  (save-excursion
    (bookmark-jump "org-capture-last-stored")
    (org-entry-put nil "STATUS" "queued")
    (org-capture-ai--log "Entry marked as queued")))

(defun org-capture-ai--async-process ()
  "Fetch URL and process with LLM asynchronously."
  (save-excursion
    (bookmark-jump "org-capture-last-stored")
    (let ((url (org-entry-get nil "URL"))
          (marker (point-marker)))

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
          (org-capture-ai--process-html html-content marker))

        ;; Error callback
        (lambda (error)
          (org-capture-ai--set-status marker "fetch-error" (format "%s" error))
          (message "org-capture-ai: Failed to fetch URL: %s" error)
          (set-marker marker nil))))))

(defun org-capture-ai--process-html (html-content marker)
  "Extract content from HTML-CONTENT and send to LLM.
Update entry at MARKER with results."
  (let* ((metadata (org-capture-ai-extract-metadata html-content))
         (clean-text (org-capture-ai-extract-readable-content html-content))
         (title (plist-get metadata :title)))

    (org-capture-ai--log "Extracted %d chars of text, title: %s"
                         (length clean-text) title)

    (save-excursion
      (org-with-point-at marker
        (org-capture-ai--set-status marker "processing")
        (org-entry-put nil "EXTRACTED_TITLE" title)))

    ;; Process with LLM
    (org-capture-ai--llm-analyze clean-text marker)))

(defun org-capture-ai--llm-analyze (text marker)
  "Analyze TEXT with LLM and update entry at MARKER."
  ;; First: Generate summary
  (org-capture-ai-llm-summarize text
    (lambda (summary)
      (when summary
        (save-excursion
          (org-with-point-at marker
            (org-entry-put nil "AI_SUMMARY" summary)
            (org-entry-put nil "AI_MODEL" (symbol-name gptel-model))))

        ;; Second: Extract tags
        (org-capture-ai-llm-extract-tags text
          (lambda (tags)
            (if tags
                (save-excursion
                  (org-with-point-at marker
                    ;; Save as property
                    (org-entry-put nil "AI_TAGS" (mapconcat #'identity tags " "))

                    ;; Also add as org tags
                    (org-set-tags (append (org-get-tags) tags))

                    ;; Mark complete
                    (org-capture-ai--set-status marker "completed")
                    (org-entry-put nil "PROCESSED_AT"
                                   (format-time-string "[%Y-%m-%d %a %H:%M]"))

                    (message "org-capture-ai: Processing complete")))
              (org-capture-ai--set-status marker "error" "Tag extraction failed"))

            ;; Clean up marker
            (set-marker marker nil)))))))

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
               (org-capture-ai--process-html html-content marker))
             (lambda (error)
               (org-capture-ai--set-status marker "fetch-error" (format "%s" error))
               (set-marker marker nil))))))
     "STATUS=\"queued\""
     (list org-capture-ai-default-file))
    (message "org-capture-ai: Started processing %d queued entries" processed)))

(defun org-capture-ai-reprocess-entry ()
  "Manually reprocess the org entry at point."
  (interactive)
  (let ((url (org-entry-get nil "URL"))
        (marker (point-marker)))
    (if url
        (progn
          (org-capture-ai--set-status marker "reprocessing")
          (org-capture-ai-fetch-url url
            (lambda (html-content)
              (org-capture-ai--process-html html-content marker))
            (lambda (error)
              (org-capture-ai--set-status marker "fetch-error" (format "%s" error))
              (set-marker marker nil)))
          (message "org-capture-ai: Reprocessing %s" url))
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
                 (file ,org-capture-ai-default-file)
                 "* %^{Title}\n:PROPERTIES:\n:URL: %^{URL}\n:CAPTURED: %U\n:STATUS: processing\n:END:\n\n%?"
                 :empty-lines 1
                 :after-finalize org-capture-ai--process-entry))

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
