;;; org-capture-ai-test.el --- Tests for org-capture-ai -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for org-capture-ai using ERT (Emacs Lisp Regression Testing)

;;; Code:

(require 'ert)
(require 'org-capture-ai)

;;; Test Fixtures

(defconst org-capture-ai-test--sample-html
  "<!DOCTYPE html>
<html>
<head>
  <title>Test Article Title</title>
  <meta name=\"description\" content=\"This is a test description\">
</head>
<body>
  <nav>Navigation Menu</nav>
  <article>
    <h1>Main Article Content</h1>
    <p>This is the main content of the article.</p>
    <p>It contains multiple paragraphs.</p>
  </article>
  <aside class=\"sidebar\">Sidebar content</aside>
  <footer>Footer content</footer>
  <script>console.log('test');</script>
</body>
</html>"
  "Sample HTML for testing.")

(defconst org-capture-ai-test--sample-html-no-article
  "<!DOCTYPE html>
<html>
<head><title>Simple Page</title></head>
<body>
  <div>Just some body content here.</div>
</body>
</html>"
  "Sample HTML without article tag.")

;;; Test Helpers

(defmacro org-capture-ai-test--with-temp-org-buffer (&rest body)
  "Execute BODY in a temporary org-mode buffer."
  `(with-temp-buffer
     (org-mode)
     ,@body))

(defun org-capture-ai-test--create-mock-entry (url)
  "Create a mock org entry with URL property."
  (org-capture-ai-test--with-temp-org-buffer
   (insert "* Test Entry\n")
   (insert ":PROPERTIES:\n")
   (insert (format ":URL: %s\n" url))
   (insert ":END:\n")
   (goto-char (point-min))
   (point-marker)))

;;; HTML Processing Tests

(ert-deftest org-capture-ai-test-parse-html ()
  "Test HTML parsing returns a valid DOM."
  (let ((dom (org-capture-ai-parse-html org-capture-ai-test--sample-html)))
    (should dom)
    (should (listp dom))
    (should (eq (dom-tag dom) 'html))))

(ert-deftest org-capture-ai-test-extract-metadata ()
  "Test metadata extraction from HTML."
  (let ((metadata (org-capture-ai-extract-metadata org-capture-ai-test--sample-html)))
    (should (plist-get metadata :title))
    (should (string= (plist-get metadata :title) "Test Article Title"))
    (should (plist-get metadata :description))
    (should (string= (plist-get metadata :description) "This is a test description"))))

(ert-deftest org-capture-ai-test-extract-metadata-no-meta ()
  "Test metadata extraction handles missing meta tags."
  (let ((metadata (org-capture-ai-extract-metadata org-capture-ai-test--sample-html-no-article)))
    (should (string= (plist-get metadata :title) "Simple Page"))
    (should (string= (plist-get metadata :description) ""))))

(ert-deftest org-capture-ai-test-extract-readable-content ()
  "Test extraction of readable content filters noise."
  (let ((content (org-capture-ai-extract-readable-content org-capture-ai-test--sample-html)))
    (should content)
    (should (string-match-p "Main Article Content" content))
    (should (string-match-p "main content of the article" content))
    ;; Should NOT contain navigation, footer, sidebar, or script
    (should-not (string-match-p "Navigation Menu" content))
    (should-not (string-match-p "Footer content" content))
    (should-not (string-match-p "Sidebar content" content))
    (should-not (string-match-p "console.log" content))))

(ert-deftest org-capture-ai-test-extract-readable-content-fallback ()
  "Test content extraction falls back to body if no article tag."
  (let ((content (org-capture-ai-extract-readable-content org-capture-ai-test--sample-html-no-article)))
    (should content)
    (should (string-match-p "Just some body content" content))))

;;; Status Management Tests

(ert-deftest org-capture-ai-test-set-status ()
  "Test setting status on an org entry."
  (org-capture-ai-test--with-temp-org-buffer
   (insert "* Test Entry\n")
   (insert ":PROPERTIES:\n")
   (insert ":END:\n")
   (goto-char (point-min))
   (let ((marker (point-marker)))
     (org-capture-ai--set-status marker "processing")
     (should (string= (org-entry-get nil "STATUS") "processing"))
     (should (org-entry-get nil "UPDATED_AT"))
     (set-marker marker nil))))

(ert-deftest org-capture-ai-test-set-status-with-error ()
  "Test setting status with error message."
  (org-capture-ai-test--with-temp-org-buffer
   (insert "* Test Entry\n")
   (insert ":PROPERTIES:\n")
   (insert ":END:\n")
   (goto-char (point-min))
   (let ((marker (point-marker)))
     (org-capture-ai--set-status marker "error" "Test error message")
     (should (string= (org-entry-get nil "STATUS") "error"))
     (should (string= (org-entry-get nil "ERROR") "Test error message"))
     (set-marker marker nil))))

;;; Logging Tests

(ert-deftest org-capture-ai-test-logging-enabled ()
  "Test that logging creates messages when enabled."
  (let ((org-capture-ai-enable-logging t))
    (with-current-buffer (get-buffer-create "*org-capture-ai-log*")
      (erase-buffer))
    (org-capture-ai--log "Test message: %s" "hello")
    (with-current-buffer "*org-capture-ai-log*"
      (should (> (buffer-size) 0))
      (should (string-match-p "Test message: hello" (buffer-string))))))

(ert-deftest org-capture-ai-test-logging-disabled ()
  "Test that logging is skipped when disabled."
  (let ((org-capture-ai-enable-logging nil)
        (initial-size 0))
    (when (get-buffer "*org-capture-ai-log*")
      (with-current-buffer "*org-capture-ai-log*"
        (setq initial-size (buffer-size))))
    (org-capture-ai--log "This should not be logged")
    (when (get-buffer "*org-capture-ai-log*")
      (with-current-buffer "*org-capture-ai-log*"
        (should (= (buffer-size) initial-size))))))

;;; Configuration Tests

(ert-deftest org-capture-ai-test-default-configuration ()
  "Test default configuration values are set."
  (should org-capture-ai-default-file)
  (should org-capture-ai-template-key)
  (should (numberp org-capture-ai-summary-sentences))
  (should (> org-capture-ai-summary-sentences 0))
  (should (numberp org-capture-ai-tag-count))
  (should (> org-capture-ai-tag-count 0))
  (should (numberp org-capture-ai-max-retries))
  (should (> org-capture-ai-max-retries 0)))

;;; Mock LLM Tests

(defvar org-capture-ai-test--mock-llm-response nil
  "Mock response for LLM requests in tests.")

(defun org-capture-ai-test--mock-gptel-request (prompt &rest args)
  "Mock gptel-request for testing.
PROMPT and ARGS are ignored in mock."
  (let ((callback (plist-get args :callback)))
    (when callback
      (funcall callback org-capture-ai-test--mock-llm-response
               (list :status "success")))))

(ert-deftest org-capture-ai-test-llm-summarize-success ()
  "Test LLM summarization with mocked successful response."
  (let ((org-capture-ai-test--mock-llm-response "This is a test summary."))
    (cl-letf (((symbol-function 'gptel-request) #'org-capture-ai-test--mock-gptel-request))
      (let ((result nil))
        (org-capture-ai-llm-summarize "Test text"
          (lambda (summary)
            (setq result summary)))
        (should (string= result "This is a test summary."))))))

(ert-deftest org-capture-ai-test-llm-summarize-failure ()
  "Test LLM summarization handles failures gracefully."
  (let ((org-capture-ai-test--mock-llm-response nil))
    (cl-letf (((symbol-function 'gptel-request) #'org-capture-ai-test--mock-gptel-request))
      (let ((result nil))
        (org-capture-ai-llm-summarize "Test text"
          (lambda (summary)
            (setq result summary)))
        (should result)
        (should (string-match-p "Summarization failed" result))))))

(ert-deftest org-capture-ai-test-llm-extract-tags-success ()
  "Test tag extraction with mocked successful response."
  (let ((org-capture-ai-test--mock-llm-response "emacs, org-mode, ai, testing"))
    (cl-letf (((symbol-function 'gptel-request) #'org-capture-ai-test--mock-gptel-request))
      (let ((result nil))
        (org-capture-ai-llm-extract-tags "Test text"
          (lambda (tags)
            (setq result tags)))
        (should (listp result))
        (should (= (length result) 4))
        (should (member "emacs" result))
        (should (member "org-mode" result))))))

(ert-deftest org-capture-ai-test-llm-extract-tags-failure ()
  "Test tag extraction handles failures."
  (let ((org-capture-ai-test--mock-llm-response nil))
    (cl-letf (((symbol-function 'gptel-request) #'org-capture-ai-test--mock-gptel-request))
      (let ((result 'not-set))
        (org-capture-ai-llm-extract-tags "Test text"
          (lambda (tags)
            (setq result tags)))
        (should (null result))))))

;;; Integration Tests (require manual inspection)

(ert-deftest org-capture-ai-test-setup-teardown ()
  "Test setup and teardown functions."
  (let ((initial-templates org-capture-templates)
        (initial-hooks (member 'org-capture-ai--process-entry
                               org-capture-after-finalize-hook)))

    ;; Setup
    (org-capture-ai-setup)
    (should (member 'org-capture-ai--process-entry
                    org-capture-after-finalize-hook))

    ;; Teardown
    (org-capture-ai-teardown)
    (should-not (member 'org-capture-ai--process-entry
                        org-capture-after-finalize-hook))

    ;; Restore initial state
    (setq org-capture-templates initial-templates)))

;;; Run All Tests

(defun org-capture-ai-run-tests ()
  "Run all org-capture-ai tests."
  (interactive)
  (ert-run-tests-interactively "^org-capture-ai-test-"))

(provide 'org-capture-ai-test)
;;; org-capture-ai-test.el ends here
