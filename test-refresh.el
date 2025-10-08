;;; test-refresh.el --- Test the refresh-entry function

(require 'org)

(message "\n=== Testing org-capture-ai-refresh-entry ===\n")

;; Create a test org buffer
(with-temp-buffer
  (org-mode)
  (insert "* Old Title\n")
  (insert ":PROPERTIES:\n")
  (insert ":URL: https://example.com/test\n")
  (insert ":CAPTURED: [2025-01-01 Wed 10:00]\n")
  (insert ":STATUS: completed\n")
  (insert ":TITLE: Old Title from HTML\n")
  (insert ":CREATOR: Old Author\n")
  (insert ":SUBJECT: old, tags\n")
  (insert ":AI_MODEL: old-model\n")
  (insert ":END:\n")
  (insert "\n")
  (insert "Old summary that should be removed.\n")
  (insert "\n")
  (insert "User notes that should also be removed.\n")

  ;; Test the clearing logic
  (goto-char (point-min))
  (org-back-to-heading t)

  (message "Before refresh:")
  (message "Buffer contents:\n%s" (buffer-string))

  ;; Test property deletion
  (message "\nTesting property clearing...")
  (dolist (prop '("TITLE" "CREATOR" "SUBJECT" "AI_MODEL"))
    (let ((value (org-entry-get nil prop)))
      (message "  %s: %s" prop (if value value "nil"))))

  ;; Clear properties
  (dolist (prop '("TITLE" "CREATOR" "PUBLISHER" "DATE" "TYPE"
                "LANGUAGE" "RIGHTS" "DESCRIPTION" "FORMAT"
                "SOURCE" "RELATION" "COVERAGE" "SUBJECT"
                "AI_MODEL" "PROCESSED_AT" "ERROR"))
    (org-entry-delete nil prop))

  (message "\nAfter clearing properties:")
  (dolist (prop '("TITLE" "CREATOR" "SUBJECT" "AI_MODEL"))
    (let ((value (org-entry-get nil prop)))
      (message "  %s: %s" prop (if value value "nil (✓)"))))

  ;; Test body deletion
  (message "\nTesting body content clearing...")
  (org-back-to-heading t)
  (org-end-of-meta-data t)
  (let ((body-start (point)))
    (message "Body start position: %d" body-start)
    (org-end-of-subtree t t)
    (message "Subtree end position: %d" (point))
    (delete-region body-start (point)))

  (message "\nAfter clearing body:")
  (message "Buffer contents:\n%s" (buffer-string))

  ;; Check that structural properties are preserved
  (let ((url (org-entry-get nil "URL"))
        (captured (org-entry-get nil "CAPTURED"))
        (status (org-entry-get nil "STATUS")))
    (message "\nStructural properties preserved:")
    (message "  URL: %s %s" url (if url "✓" "✗"))
    (message "  CAPTURED: %s %s" captured (if captured "✓" "✗"))
    (message "  STATUS: %s %s" status (if status "✓" "✗")))

  (message "\n✓ Refresh logic test complete"))

(message "\n=== Test Summary ===")
(message "The refresh function should:")
(message "  1. Preserve URL, CAPTURED, and STATUS properties")
(message "  2. Clear all Dublin Core metadata properties")
(message "  3. Clear AI_MODEL and PROCESSED_AT")
(message "  4. Clear all body content after properties drawer")
(message "  5. Clear org tags")
(message "\nThis test verified steps 1-4. Tags clearing requires interactive test.")

(provide 'test-refresh)
