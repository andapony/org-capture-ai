;;; org-capture-ai-test-helpers.el --- Test utilities for org-capture-ai -*- lexical-binding: t; -*-

;;; Commentary:
;; Shared test utilities, fixtures, and assertions for org-capture-ai tests

;;; Code:

(require 'ert)
(require 'org)

;;; Test Fixtures and Data

(defvar org-capture-ai-test--temp-files nil
  "List of temporary files created during testing for cleanup.")

(defun org-capture-ai-test--create-temp-org-file ()
  "Create a temporary org file with Bookmarks heading.
Returns the file path. File will be automatically cleaned up."
  (let ((temp-file (make-temp-file "org-capture-ai-test-" nil ".org")))
    (with-temp-file temp-file
      (insert "#+OPTIONS: ^:{}\n\n* Bookmarks\n"))
    (push temp-file org-capture-ai-test--temp-files)
    temp-file))

(defun org-capture-ai-test--cleanup-temp-files ()
  "Delete all temporary files created during testing."
  (dolist (file org-capture-ai-test--temp-files)
    (when (file-exists-p file)
      (delete-file file)))
  (setq org-capture-ai-test--temp-files nil))

;;; Fixture Loading

(defun org-capture-ai-test--fixture-path (category name)
  "Return path to fixture file in CATEGORY with NAME."
  (let ((base-dir (or (and load-file-name (file-name-directory load-file-name))
                      (and buffer-file-name (file-name-directory buffer-file-name))
                      default-directory)))
    (expand-file-name (format "test-fixtures/%s/%s" category name) base-dir)))

(defun org-capture-ai-test--load-fixture (category name)
  "Load fixture file from CATEGORY with NAME.
Returns file contents as string."
  (let ((path (org-capture-ai-test--fixture-path category name)))
    (if (file-exists-p path)
        (with-temp-buffer
          (insert-file-contents path)
          (buffer-string))
      (error "Fixture not found: %s/%s" category name))))

(defun org-capture-ai-test--fixture-exists-p (category name)
  "Return non-nil if fixture exists in CATEGORY with NAME."
  (file-exists-p (org-capture-ai-test--fixture-path category name)))

;;; Assertion Helpers

(defun org-capture-ai-test--assert-properties (expected-props)
  "Assert that current org entry has EXPECTED-PROPS.
EXPECTED-PROPS is an alist of (PROPERTY-NAME . EXPECTED-VALUE).
Fails if any property doesn't match."
  (org-back-to-heading t)
  (dolist (prop expected-props)
    (let* ((key (car prop))
           (expected-value (cdr prop))
           (actual-value (org-entry-get nil key)))
      (should (equal actual-value expected-value)))))

(defun org-capture-ai-test--assert-no-orphaned-drawers (buffer)
  "Assert BUFFER has no orphaned properties drawers.
An orphaned drawer is a :PROPERTIES: block without a heading above it."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "^:PROPERTIES:" nil t)
        (save-excursion
          (forward-line -1)
          (beginning-of-line)
          ;; Previous line should be a heading or blank/content (not another property)
          (should (or (looking-at "^\\*")
                      (looking-at "^[ \t]*$")
                      (looking-at "^[^:]"))))))))

(defun org-capture-ai-test--assert-single-properties-drawer ()
  "Assert current org entry has exactly one properties drawer."
  (org-back-to-heading t)
  (let ((heading-start (point))
        (heading-end (save-excursion (outline-next-heading) (point))))
    (should (= 1 (how-many "^:PROPERTIES:" heading-start heading-end)))))

(defun org-capture-ai-test--assert-properties-drawer-structure ()
  "Assert properties drawer is well-formed with matching :PROPERTIES: and :END:."
  (org-back-to-heading t)
  (let ((found-properties nil)
        (found-end nil))
    (save-excursion
      (when (re-search-forward "^:PROPERTIES:" (save-excursion (outline-next-heading) (point)) t)
        (setq found-properties t)
        (when (re-search-forward "^:END:" (save-excursion (outline-next-heading) (point)) t)
          (setq found-end t))))
    (should found-properties)
    (should found-end)))

(defun org-capture-ai-test--count-properties-drawers ()
  "Count total :PROPERTIES: drawers in current buffer."
  (how-many "^:PROPERTIES:" (point-min) (point-max)))

;;; Mock Helpers

(defvar org-capture-ai-test--mock-llm-call-count 0
  "Count of LLM calls during test.")

(defvar org-capture-ai-test--mock-llm-responses
  '((:summary . "TITLE: Test Title\nSUMMARY: This is a test summary. It has multiple sentences. Testing works.")
    (:tags . "article, test, emacs")
    (:takeaways . "1. Testing is important for reliability.\n2. Emacs is highly extensible.\n3. Async code requires careful design."))
  "Default mock LLM responses.")

(defun org-capture-ai-test--mock-gptel-request (text &rest args)
  "Mock gptel-request for testing.
Calls callback synchronously with response based on system message."
  (setq org-capture-ai-test--mock-llm-call-count
        (1+ org-capture-ai-test--mock-llm-call-count))
  (let ((callback (plist-get args :callback))
        (system-msg (plist-get args :system)))
    (message "[MOCK] gptel-request called (#%d)" org-capture-ai-test--mock-llm-call-count)
    (let ((response (cond
                     ((string-match "title and.*summary" system-msg)
                      (cdr (assq :summary org-capture-ai-test--mock-llm-responses)))
                     ((string-match "tags" system-msg)
                      (cdr (assq :tags org-capture-ai-test--mock-llm-responses)))
                     ((string-match "takeaway" system-msg)
                      (cdr (assq :takeaways org-capture-ai-test--mock-llm-responses)))
                     (t "mock response"))))
      ;; Call callback synchronously for easier testing
      (funcall callback response nil))))

(defvar org-capture-ai-test--mock-html-response
  "<!DOCTYPE html>
<html>
<head>
  <title>Test Page</title>
  <meta name=\"description\" content=\"Test description\">
  <meta name=\"author\" content=\"Test Author\">
</head>
<body>
  <article>
    <h1>Main Content</h1>
    <p>This is test content for the article.</p>
    <p>It has multiple paragraphs.</p>
  </article>
</body>
</html>"
  "Default mock HTML response.")

(defvar org-capture-ai-test--mock-fetch-should-fail nil
  "When non-nil, mock fetch will call error callback.")

(defvar org-capture-ai-test--mock-fetch-error-message "Network error"
  "Error message for mock fetch failures.")

(defun org-capture-ai-test--mock-fetch-url (url success-cb error-cb)
  "Mock URL fetch for testing.
Calls SUCCESS-CB with HTML or ERROR-CB based on test configuration."
  (message "[MOCK] fetch-url called for: %s" url)
  (if org-capture-ai-test--mock-fetch-should-fail
      (funcall error-cb org-capture-ai-test--mock-fetch-error-message)
    (funcall success-cb org-capture-ai-test--mock-html-response)))

;;; Test Environment Macro

(defmacro org-capture-ai-test--with-mocked-env (&rest body)
  "Execute BODY with mocked LLM and URL fetching.
Automatically creates temp file, installs mocks, and cleans up."
  `(let ((org-capture-ai-test--temp-file (org-capture-ai-test--create-temp-org-file))
         (org-capture-ai-test--mock-llm-call-count 0)
         (org-capture-ai-test--mock-fetch-should-fail nil)
         (org-capture-ai-enable-logging t))
     (unwind-protect
         (progn
           ;; Install mocks
           (advice-add 'gptel-request
                       :override #'org-capture-ai-test--mock-gptel-request)
           (advice-add 'org-capture-ai-fetch-url
                       :override #'org-capture-ai-test--mock-fetch-url)

           ;; Execute test body
           ,@body)

       ;; Cleanup
       (advice-remove 'gptel-request #'org-capture-ai-test--mock-gptel-request)
       (advice-remove 'org-capture-ai-fetch-url #'org-capture-ai-test--mock-fetch-url)
       (org-capture-ai-test--cleanup-temp-files))))

;;; Test Entry Creation

(defun org-capture-ai-test--create-processing-entry (url &optional extra-props)
  "Create a test entry in processing state with URL.
EXTRA-PROPS is optional alist of additional properties to set.
Returns a marker pointing to the entry."
  (goto-char (point-max))
  (insert "** Processing...\n")
  (insert ":PROPERTIES:\n")
  (insert ":URL: " url "\n")
  (insert ":CAPTURED: [2025-10-27 Mon 15:00]\n")
  (insert ":STATUS: processing\n")
  (dolist (prop extra-props)
    (insert (format ":%s: %s\n" (car prop) (cdr prop))))
  (insert ":END:\n\n")
  (org-back-to-heading t)
  (point-marker))

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

(defun org-capture-ai-test--wait-for-processing (marker &optional max-wait)
  "Wait for entry at MARKER to finish processing.
MAX-WAIT is max iterations (default 100, ~10 seconds).
Returns final STATUS value or nil if marker was invalidated."
  (let ((max-wait (or max-wait 100)))
    ;; Check if marker is still valid
    (when (and marker (marker-buffer marker))
      (org-with-point-at marker
        (while (and (> max-wait 0)
                    (marker-buffer marker)  ; Check marker still valid
                    (string= (org-entry-get nil "STATUS") "processing"))
          (sit-for 0.1)
          (setq max-wait (1- max-wait))))
      ;; Return final status (if marker still valid)
      (when (marker-buffer marker)
        (org-with-point-at marker
          (org-entry-get nil "STATUS"))))))

;;; Snapshot Testing

(defun org-capture-ai-test--snapshot-path (test-name)
  "Return path to snapshot file for TEST-NAME."
  (org-capture-ai-test--fixture-path "snapshots" (concat test-name ".org")))

(defun org-capture-ai-test--save-snapshot (test-name content)
  "Save CONTENT as snapshot for TEST-NAME."
  (let ((path (org-capture-ai-test--snapshot-path test-name)))
    (make-directory (file-name-directory path) t)
    (write-region content nil path)))

(defun org-capture-ai-test--compare-snapshot (test-name content &optional update)
  "Compare CONTENT against saved snapshot for TEST-NAME.
If UPDATE is non-nil, update the snapshot instead of comparing."
  (let ((path (org-capture-ai-test--snapshot-path test-name)))
    (if (or update (not (file-exists-p path)))
        (progn
          (org-capture-ai-test--save-snapshot test-name content)
          (message "Snapshot %s: %s" (if update "updated" "created") test-name))
      (let ((expected (with-temp-buffer
                        (insert-file-contents path)
                        (buffer-string))))
        (should (equal content expected))))))

;;; Performance Helpers

(defmacro org-capture-ai-test--measure-time (&rest body)
  "Execute BODY and return elapsed time in seconds."
  `(let ((start-time (current-time)))
     ,@body
     (float-time (time-subtract (current-time) start-time))))

(provide 'org-capture-ai-test-helpers)
;;; org-capture-ai-test-helpers.el ends here
