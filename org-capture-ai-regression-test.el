;;; org-capture-ai-regression-test.el --- Regression tests for specific bugs -*- lexical-binding: t; -*-

;;; Commentary:
;; Each test in this file corresponds to a specific bug that was found and fixed.
;; Tests are named with the date or issue number for tracking.

;;; Code:

(require 'ert)
(require 'org-capture-ai)
(require 'org-capture-ai-test-helpers)

;;; Regression Tests

(ert-deftest org-capture-ai-regression-20251027-multiline-description ()
  "Regression: Multi-line DESCRIPTION breaks properties drawer.

Bug: When HTML meta description contains newlines, org-entry-put
inserts them directly into properties drawer, breaking the drawer
structure and creating orphaned :PROPERTIES: blocks.

Root cause: org-entry-put doesn't sanitize newlines in values.

Fix: Added org-capture-ai--sanitize-property-value function that:
- Replaces newlines with spaces
- Collapses multiple spaces
- Truncates to 500 chars

Date: 2025-10-27
File: org-capture-ai.el lines 688-703, 721-744"
  (org-capture-ai-test--with-mocked-env
   ;; Use fixture with multi-line description
   (setq org-capture-ai-test--mock-html-response
         (org-capture-ai-test--load-fixture "html" "multiline-description.html"))

   (with-current-buffer (find-file-noselect org-capture-ai-test--temp-file)
     (let* ((marker (org-capture-ai-test--create-processing-entry
                     "https://example.com/multiline-test"))
            (entry-pos (marker-position marker)))  ; Save position

       ;; Process the entry (marker will be invalidated)
       (org-capture-ai--async-process marker)

       ;; Wait for completion
       (org-capture-ai-test--wait-for-processing marker)

       ;; Navigate back to entry
       (goto-char entry-pos)
       (org-back-to-heading t)

       ;; Critical assertion: Only ONE properties drawer
       (should (= 1 (org-capture-ai-test--count-properties-drawers)))

       ;; Should complete successfully
       (should (equal (org-entry-get nil "STATUS") "completed"))

       ;; Verify DESCRIPTION is single-line (no literal newlines)
       (let ((description (org-entry-get nil "DESCRIPTION")))
         (when description
           (should-not (string-match-p "\n" description))))

       ;; Verify no orphaned drawers
       (org-capture-ai-test--assert-no-orphaned-drawers (current-buffer))))))

(ert-deftest org-capture-ai-regression-20251027-duplicate-processing ()
  "Regression: Hook registered multiple times causes duplicate processing.

Bug: Calling org-capture-ai-setup multiple times (e.g., after reload)
adds the hook multiple times, causing entries to be processed multiple
times and creating duplicate properties drawers.

Root cause: Hook was added without removing first.

Fix: Made setup idempotent by removing hook before adding:
  (remove-hook 'org-capture-after-finalize-hook #'org-capture-ai--process-entry)
  (add-hook 'org-capture-after-finalize-hook #'org-capture-ai--process-entry)

Date: 2025-10-27
File: org-capture-ai.el lines 932-933"
  (org-capture-ai-test--with-mocked-env
   (let ((org-capture-ai-default-file org-capture-ai-test--temp-file))
     ;; Simulate user reloading config multiple times
     (org-capture-ai-teardown)
     (org-capture-ai-setup)
     (org-capture-ai-setup)  ; Second call - should not duplicate hook
     (org-capture-ai-setup)  ; Third call

     (with-current-buffer (find-file-noselect org-capture-ai-test--temp-file)
       (let ((marker (org-capture-ai-test--create-processing-entry
                      "https://example.com/test")))

         ;; Manually trigger hook (simulates org-capture finalization)
         (setq org-note-abort nil)
         (bookmark-set "org-capture-last-stored")
         (run-hooks 'org-capture-after-finalize-hook)

         ;; Wait for processing
         (org-capture-ai-test--wait-for-processing marker)

         ;; Should only have ONE properties drawer despite multiple setup calls
         (should (= 1 (org-capture-ai-test--count-properties-drawers)))

         ;; Should only call LLM three times (summary + tags + takeaways), not 9 times
         (should (= 3 org-capture-ai-test--mock-llm-call-count)))))))

(ert-deftest org-capture-ai-regression-20251027-heading-replacement ()
  "Regression: replace-match destroys heading structure.

Bug: Original code used replace-match with org-complex-heading-regexp
to update heading title. This destroys tags and drawer structure.

Root cause: replace-match at beginning-of-line replaces entire heading
line including tags.

Fix: Use org-edit-headline API which properly preserves tags:
  (org-edit-headline title)

Date: 2025-10-27
File: org-capture-ai.el line 785 (was lines 754-758)"
  (org-capture-ai-test--with-mocked-env
   (with-current-buffer (find-file-noselect org-capture-ai-test--temp-file)
     (let* ((marker (org-capture-ai-test--create-processing-entry
                     "https://example.com/test"))
            (entry-pos (marker-position marker)))  ; Save position

       ;; Add tags to the initial entry
       (org-with-point-at marker
         (org-set-tags '("initial" "tags")))

       ;; Process (will update heading and invalidate marker)
       (org-capture-ai--async-process marker)
       (org-capture-ai-test--wait-for-processing marker)

       ;; Navigate back to entry using saved position
       (goto-char entry-pos)
       (org-back-to-heading t)

       ;; Verify heading was updated
       (should (string= (org-get-heading t t t t) "Test Title"))

       ;; Verify tags were preserved (and new ones added)
       (let ((tags (org-get-tags)))
         ;; Should have test tags from LLM response
         (should (member "test" tags)))

       ;; Verify properties drawer is intact
       (org-capture-ai-test--assert-single-properties-drawer)
       (org-capture-ai-test--assert-properties-drawer-structure)))))

(ert-deftest org-capture-ai-regression-unit-sanitize-property-value ()
  "Unit test for org-capture-ai--sanitize-property-value function.

This is a unit test for the specific sanitization function that
fixed the multi-line description bug."
  ;; Test newline replacement
  (should (equal "First line Second line"
                 (org-capture-ai--sanitize-property-value "First line\nSecond line")))

  ;; Test multiple newlines
  (should (equal "Line 1 Line 2 Line 3"
                 (org-capture-ai--sanitize-property-value "Line 1\n\nLine 2\n\n\nLine 3")))

  ;; Test whitespace collapsing
  (should (equal "Multiple spaces"
                 (org-capture-ai--sanitize-property-value "Multiple    spaces")))

  ;; Test truncation (> 500 chars)
  (let ((long-string (make-string 600 ?x)))
    (let ((result (org-capture-ai--sanitize-property-value long-string)))
      (should (= 500 (length result)))
      (should (string-suffix-p "..." result))))

  ;; Test nil handling
  (should (null (org-capture-ai--sanitize-property-value nil)))

  ;; Test empty string
  (should (equal "" (org-capture-ai--sanitize-property-value "")))

  ;; Test trimming
  (should (equal "trimmed"
                 (org-capture-ai--sanitize-property-value "  trimmed  "))))

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
         (org-capture-ai-default-file org-capture-ai-test--temp-file)
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
         (org-capture-ai-default-file org-capture-ai-test--temp-file)
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
         (should (null (org-entry-get nil "TAKEAWAYS"))))))))

(provide 'org-capture-ai-regression-test)
;;; org-capture-ai-regression-test.el ends here
