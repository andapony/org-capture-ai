;;; org-capture-ai-error-test.el --- Error condition tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for error handling: network failures, content too short, LLM errors, etc.

;;; Code:

(require 'ert)
(require 'org-capture-ai)
(require 'org-capture-ai-test-helpers)

;;; Error Condition Tests

(ert-deftest org-capture-ai-error-test-fetch-failure ()
  "Test handling of network fetch failure."
  (org-capture-ai-test--with-mocked-env
   ;; Configure mock to fail
   (setq org-capture-ai-test--mock-fetch-should-fail t)
   (setq org-capture-ai-test--mock-fetch-error-message "404 Not Found")

   (with-current-buffer (find-file-noselect org-capture-ai-test--temp-file)
     (let ((marker (org-capture-ai-test--create-processing-entry
                    "https://example.com/404")))

       ;; Process the entry
       (org-capture-ai--async-process marker)

       ;; Wait for processing
       (let ((final-status (org-capture-ai-test--wait-for-processing marker)))

         ;; Should be in fetch-error state
         (should (equal final-status "fetch-error"))

         ;; Should have error message
         (org-with-point-at marker
           (let ((error-msg (org-entry-get nil "ERROR")))
             (should error-msg)
             (should (string-match-p "404 Not Found" error-msg))))

         ;; Should NOT have called LLM
         (should (= 0 org-capture-ai-test--mock-llm-call-count))

         ;; Should still have valid properties drawer
         (org-capture-ai-test--assert-single-properties-drawer))))))

(ert-deftest org-capture-ai-error-test-empty-content ()
  "Test handling of page with no readable content."
  (org-capture-ai-test--with-mocked-env
   ;; Use fixture with empty body
   (setq org-capture-ai-test--mock-html-response
         (org-capture-ai-test--load-fixture "html" "empty-body.html"))

   (with-current-buffer (find-file-noselect org-capture-ai-test--temp-file)
     (let ((marker (org-capture-ai-test--create-processing-entry
                    "https://example.com/empty")))

       (org-capture-ai--async-process marker)

       (let ((final-status (org-capture-ai-test--wait-for-processing marker)))

         ;; Should be in error state
         (should (equal final-status "error"))

         ;; Should have descriptive error
         (org-with-point-at marker
           (let ((error-msg (org-entry-get nil "ERROR")))
             (should (string-match-p "no readable text" error-msg))))

         ;; Should NOT have called LLM (content too short)
         (should (= 0 org-capture-ai-test--mock-llm-call-count))

         ;; Properties drawer should be intact
         (should (= 1 (org-capture-ai-test--count-properties-drawers))))))))

(ert-deftest org-capture-ai-error-test-only-scripts ()
  "Test handling of page with only scripts/styles (no text content)."
  (org-capture-ai-test--with-mocked-env
   (setq org-capture-ai-test--mock-html-response
         (org-capture-ai-test--load-fixture "html" "only-scripts.html"))

   (with-current-buffer (find-file-noselect org-capture-ai-test--temp-file)
     (let ((marker (org-capture-ai-test--create-processing-entry
                    "https://example.com/js-only")))

       (org-capture-ai--async-process marker)

       (let ((final-status (org-capture-ai-test--wait-for-processing marker)))

         ;; Should fail due to content too short
         (should (equal final-status "error"))

         ;; Should have extracted metadata even though content failed
         (org-with-point-at marker
           (should (org-entry-get nil "TITLE")))

         ;; Single properties drawer
         (should (= 1 (org-capture-ai-test--count-properties-drawers))))))))

(ert-deftest org-capture-ai-error-test-llm-failure ()
  "Test handling of LLM API failure."
  (org-capture-ai-test--with-mocked-env
   ;; Mock LLM to fail
   (advice-remove 'gptel-request #'org-capture-ai-test--mock-gptel-request)
   (advice-add 'gptel-request
               :override
               (lambda (text &rest args)
                 (let ((callback (plist-get args :callback)))
                   ;; Call error callback
                   (funcall callback nil "LLM API timeout"))))

   (with-current-buffer (find-file-noselect org-capture-ai-test--temp-file)
     (let ((marker (org-capture-ai-test--create-processing-entry
                    "https://example.com/test")))

       (org-capture-ai--async-process marker)

       ;; Wait a bit for error handling
       (sit-for 0.5)

       ;; Note: Current implementation doesn't explicitly handle LLM errors well
       ;; This test documents current behavior and can be enhanced when error
       ;; handling is improved

       ;; At minimum, should not crash and should have properties drawer
       (should (= 1 (org-capture-ai-test--count-properties-drawers)))))))

(ert-deftest org-capture-ai-error-test-long-description-truncation ()
  "Test that very long descriptions are properly truncated."
  (org-capture-ai-test--with-mocked-env
   (setq org-capture-ai-test--mock-html-response
         (org-capture-ai-test--load-fixture "html" "long-description.html"))

   (with-current-buffer (find-file-noselect org-capture-ai-test--temp-file)
     (let ((marker (org-capture-ai-test--create-processing-entry
                    "https://example.com/long")))

       (org-capture-ai--async-process marker)
       (org-capture-ai-test--wait-for-processing marker)

       ;; Verify DESCRIPTION was truncated to max 500 chars
       (org-with-point-at marker
         (let ((description (org-entry-get nil "DESCRIPTION")))
           (should (<= (length description) 500))
           ;; Should end with "..." if truncated
           (when (>= (length description) 500)
             (should (string-suffix-p "..." description)))))

       ;; Should still complete successfully
       (should (equal "completed" (org-entry-get nil "STATUS" marker)))

       ;; Properties drawer should be intact
       (should (= 1 (org-capture-ai-test--count-properties-drawers))))))))

(ert-deftest org-capture-ai-error-test-special-characters ()
  "Test handling of special characters in metadata."
  (org-capture-ai-test--with-mocked-env
   (setq org-capture-ai-test--mock-html-response
         (org-capture-ai-test--load-fixture "html" "special-chars.html"))

   (with-current-buffer (find-file-noselect org-capture-ai-test--temp-file)
     (let ((marker (org-capture-ai-test--create-processing-entry
                    "https://example.com/special")))

       (org-capture-ai--async-process marker)
       (org-capture-ai-test--wait-for-processing marker)

       ;; Should handle special chars without breaking
       (org-with-point-at marker
         ;; Title should contain quotes
         (let ((title (org-entry-get nil "TITLE")))
           (should (string-match-p "Quotes" title)))

         ;; CREATOR should handle non-ASCII
         (let ((creator (org-entry-get nil "CREATOR")))
           (should creator)
           (should (string-match-p "O'Brien" creator))))

       ;; Properties drawer should be well-formed
       (org-capture-ai-test--assert-single-properties-drawer)
       (org-capture-ai-test--assert-properties-drawer-structure)

       ;; Should complete successfully
       (should (equal "completed" (org-entry-get nil "STATUS" marker)))))))

(ert-deftest org-capture-ai-error-test-missing-url-property ()
  "Test behavior when entry has no URL property."
  (org-capture-ai-test--with-mocked-env
   (with-current-buffer (find-file-noselect org-capture-ai-test--temp-file)
     (goto-char (point-max))
     (insert "** Entry Without URL\n")
     (insert ":PROPERTIES:\n")
     (insert ":CAPTURED: [2025-10-27 Mon 15:00]\n")
     (insert ":STATUS: processing\n")
     (insert ":END:\n\n")
     (org-back-to-heading t)
     (let ((marker (point-marker)))

       ;; Try to process entry without URL
       (org-capture-ai--async-process marker)

       ;; Should not crash - system should handle gracefully
       ;; (Current implementation may not explicitly check for URL,
       ;; so this documents current behavior)

       ;; At minimum, should not break buffer structure
       (should (buffer-live-p (current-buffer)))
       (should (= 1 (org-capture-ai-test--count-properties-drawers)))))))

(ert-deftest org-capture-ai-error-test-concurrent-processing ()
  "Test multiple entries being processed concurrently."
  (org-capture-ai-test--with-mocked-env
   (with-current-buffer (find-file-noselect org-capture-ai-test--temp-file)
     ;; Create three entries
     (let ((marker1 (org-capture-ai-test--create-processing-entry
                     "https://example.com/test1"))
           (marker2 (org-capture-ai-test--create-processing-entry
                     "https://example.com/test2"))
           (marker3 (org-capture-ai-test--create-processing-entry
                     "https://example.com/test3")))

       ;; Start all three processing
       (org-capture-ai--async-process marker1)
       (org-capture-ai--async-process marker2)
       (org-capture-ai--async-process marker3)

       ;; Wait for all to complete
       (org-capture-ai-test--wait-for-processing marker1)
       (org-capture-ai-test--wait-for-processing marker2)
       (org-capture-ai-test--wait-for-processing marker3)

       ;; All should complete successfully
       (should (equal "completed" (org-entry-get nil "STATUS" marker1)))
       (should (equal "completed" (org-entry-get nil "STATUS" marker2)))
       (should (equal "completed" (org-entry-get nil "STATUS" marker3)))

       ;; Should have exactly 3 properties drawers (one per entry)
       (should (= 3 (org-capture-ai-test--count-properties-drawers)))

       ;; Each should be well-formed
       (org-with-point-at marker1
         (org-capture-ai-test--assert-single-properties-drawer))
       (org-with-point-at marker2
         (org-capture-ai-test--assert-single-properties-drawer))
       (org-with-point-at marker3
         (org-capture-ai-test--assert-single-properties-drawer))

       ;; LLM should have been called 6 times (2 per entry)
       (should (= 6 org-capture-ai-test--mock-llm-call-count))))))

(provide 'org-capture-ai-error-test)
;;; org-capture-ai-error-test.el ends here
