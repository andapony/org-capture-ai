;;; org-capture-ai-integration-test-v2.el --- Improved integration tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Integration tests using the new test helpers framework

;;; Code:

(require 'ert)
(require 'org-capture-ai)
(require 'org-capture-ai-test-helpers)

;;; Integration Tests

(ert-deftest org-capture-ai-integration-test-v2-full-capture ()
  "Test complete end-to-end capture workflow."
  (org-capture-ai-test--with-mocked-env
   ;; Use normal article fixture
   (setq org-capture-ai-test--mock-html-response
         (org-capture-ai-test--load-fixture "html" "normal-article.html"))

   (with-current-buffer (find-file-noselect org-capture-ai-test--temp-file)
     (let* ((marker (org-capture-ai-test--create-processing-entry
                     "https://example.com/test-article"))
            (entry-pos (marker-position marker)))

       ;; Process the entry
       (org-capture-ai--async-process marker)

       ;; Wait for completion
       (let ((final-status (org-capture-ai-test--wait-for-processing marker)))

         (message "\n=== FULL CAPTURE TEST ===")
         (message "LLM calls: %d" org-capture-ai-test--mock-llm-call-count)
         (message "Final status: %s" final-status)
         (message "Buffer:\n%s" (buffer-string))

         ;; Assertions using helpers
         (should (equal final-status "completed"))
         (should (= 1 (org-capture-ai-test--count-properties-drawers)))
         (should (= 3 org-capture-ai-test--mock-llm-call-count))

         ;; Verify properties
         (save-excursion
           (goto-char entry-pos)
           (org-back-to-heading t)
           (org-capture-ai-test--assert-properties
            '(("STATUS" . "completed")
              ("TITLE" . "Test Title")))
           ;; Verify drawer structure
           (org-capture-ai-test--assert-single-properties-drawer)
           (org-capture-ai-test--assert-properties-drawer-structure))

         ;; Verify no orphaned drawers
         (org-capture-ai-test--assert-no-orphaned-drawers (current-buffer)))))))

(ert-deftest org-capture-ai-integration-test-v2-with-fixture ()
  "Test using fixture library for HTML content."
  (org-capture-ai-test--with-mocked-env
   (setq org-capture-ai-test--mock-html-response
         (org-capture-ai-test--load-fixture "html" "normal-article.html"))

   (with-current-buffer (find-file-noselect org-capture-ai-test--temp-file)
     (let* ((marker (org-capture-ai-test--create-processing-entry
                     "https://example.com/fixture-test"))
            (entry-pos (marker-position marker)))

       (org-capture-ai--async-process marker)
       (org-capture-ai-test--wait-for-processing marker)

       ;; Should extract HTML metadata from fixture (CREATOR and PUBLISHER
       ;; come from HTML; TITLE is overwritten by LLM mock)
       (save-excursion
         (goto-char entry-pos)
         (org-back-to-heading t)
         (should (string= "Jane Developer" (org-entry-get nil "CREATOR")))
         (should (string= "Emacs Weekly" (org-entry-get nil "PUBLISHER"))))

       ;; Should have clean structure
       (should (= 1 (org-capture-ai-test--count-properties-drawers)))))))

(ert-deftest org-capture-ai-integration-test-v2-multiline-sanitization ()
  "Test sanitization of multi-line metadata values."
  (org-capture-ai-test--with-mocked-env
   (setq org-capture-ai-test--mock-html-response
         (org-capture-ai-test--load-fixture "html" "multiline-description.html"))

   (with-current-buffer (find-file-noselect org-capture-ai-test--temp-file)
     (let* ((marker (org-capture-ai-test--create-processing-entry
                     "https://example.com/multiline"))
            (entry-pos (marker-position marker)))

       (org-capture-ai--async-process marker)
       (let ((final-status (org-capture-ai-test--wait-for-processing marker)))

         (message "\n=== SANITIZATION TEST ===")
         (message "Status: %s" final-status)
         (message "Properties drawers: %d"
                  (org-capture-ai-test--count-properties-drawers))

         ;; Key assertion: Only one properties drawer
         (should (= 1 (org-capture-ai-test--count-properties-drawers)))

         ;; Should complete successfully
         (should (equal final-status "completed"))

         (save-excursion
           (goto-char entry-pos)
           (org-back-to-heading t)
           ;; Properties should be single-line
           (let ((description (org-entry-get nil "DESCRIPTION")))
             (when description  ; May be overwritten by LLM
               (should-not (string-match-p "\n" description))))
           ;; Drawer structure should be valid
           (org-capture-ai-test--assert-properties-drawer-structure))

         ;; No orphaned drawers
         (org-capture-ai-test--assert-no-orphaned-drawers (current-buffer)))))))

(ert-deftest org-capture-ai-integration-test-v2-idempotent-setup ()
  "Test that calling setup multiple times doesn't cause issues."
  (org-capture-ai-test--with-mocked-env
   (let ((org-capture-ai-default-file org-capture-ai-test--temp-file))
     ;; Call setup multiple times
     (org-capture-ai-teardown)
     (dotimes (_ 5)
       (org-capture-ai-setup))

     (with-current-buffer (find-file-noselect org-capture-ai-test--temp-file)
       (let ((marker (org-capture-ai-test--create-processing-entry
                      "https://example.com/idempotent")))

         ;; Simulate org-capture hook
         (setq org-note-abort nil)
         (bookmark-set "org-capture-last-stored")
         (run-hooks 'org-capture-after-finalize-hook)

         (org-capture-ai-test--wait-for-processing marker)

         ;; Should only process once
         (should (= 1 (org-capture-ai-test--count-properties-drawers)))
         (should (= 3 org-capture-ai-test--mock-llm-call-count)))))))

(ert-deftest org-capture-ai-integration-test-v2-performance ()
  "Benchmark processing time for a single entry."
  (org-capture-ai-test--with-mocked-env
   (with-current-buffer (find-file-noselect org-capture-ai-test--temp-file)
     (let* ((marker (org-capture-ai-test--create-processing-entry
                     "https://example.com/perf-test"))
            (entry-pos (marker-position marker)))

       (let ((elapsed (org-capture-ai-test--measure-time
                       (org-capture-ai--async-process marker)
                       (org-capture-ai-test--wait-for-processing marker))))

         (message "\n=== PERFORMANCE ===")
         (message "Processing time: %.3f seconds" elapsed)

         ;; With mocked I/O, should be fast (< 1 second)
         (should (< elapsed 1.0))

         ;; Should complete successfully
         (save-excursion
           (goto-char entry-pos)
           (org-back-to-heading t)
           (should (equal "completed" (org-entry-get nil "STATUS")))))))))

(defun org-capture-ai-integration-test-v2-run-all ()
  "Run all v2 integration tests."
  (interactive)
  (ert-run-tests-interactively "^org-capture-ai-integration-test-v2-"))

(provide 'org-capture-ai-integration-test-v2)
;;; org-capture-ai-integration-test-v2.el ends here
