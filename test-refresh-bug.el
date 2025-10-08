;;; test-refresh-bug.el --- Test that refresh doesn't delete next entry

(require 'org)

(message "\n=== Testing Refresh Bug Fix ===\n")

;; Create a test org buffer with two entries
(with-temp-buffer
  (org-mode)
  (insert "* First Entry\n")
  (insert ":PROPERTIES:\n")
  (insert ":URL: https://example.com/first\n")
  (insert ":STATUS: completed\n")
  (insert ":END:\n")
  (insert "\n")
  (insert "First entry body content that should be deleted.\n")
  (insert "\n")
  (insert "* Second Entry\n")
  (insert ":PROPERTIES:\n")
  (insert ":URL: https://example.com/second\n")
  (insert ":STATUS: completed\n")
  (insert ":END:\n")
  (insert "\n")
  (insert "Second entry body content that should NOT be deleted.\n")

  (message "Before deletion:")
  (message "%s" (buffer-string))

  ;; Go to first entry and delete its body
  (goto-char (point-min))
  (org-back-to-heading t)
  (org-end-of-meta-data t)
  (let ((body-start (point)))
    ;; Move to end of current entry (not including next heading)
    (org-end-of-subtree t)
    ;; Back up to before the newline that precedes next heading
    (when (and (not (eobp)) (looking-at "^\\*"))
      (forward-line -1)
      (end-of-line))
    (message "\nDeletion range: %d to %d" body-start (point))
    (delete-region body-start (point)))

  (message "\nAfter deletion:")
  (message "%s" (buffer-string))

  ;; Verify second entry still exists
  (goto-char (point-min))
  (let ((found-second nil))
    (while (and (not found-second) (not (eobp)))
      (when (looking-at "^\\* Second Entry")
        (setq found-second t))
      (forward-line 1))
    (if found-second
        (message "\n✓ SUCCESS: Second entry preserved")
      (message "\n✗ FAIL: Second entry was deleted!")))

  ;; Verify first entry body was deleted
  (goto-char (point-min))
  (let ((has-first-body (save-excursion
                          (search-forward "First entry body" nil t))))
    (if has-first-body
        (message "✗ FAIL: First entry body not deleted")
      (message "✓ SUCCESS: First entry body deleted")))

  ;; Verify second entry body was NOT deleted
  (goto-char (point-min))
  (let ((has-second-body (save-excursion
                           (search-forward "Second entry body" nil t))))
    (if has-second-body
        (message "✓ SUCCESS: Second entry body preserved")
      (message "✗ FAIL: Second entry body was deleted!"))))

(message "\n=== Test Complete ===")

(provide 'test-refresh-bug)
