;;; org-capture-ai-claude.el --- Claude/Anthropic initialization for org-capture-ai -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: AI-Generated
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (org-capture-ai "0.1.0") (gptel "0.7.0"))
;; Keywords: org, ai, capture, llm, claude, anthropic
;; URL: https://github.com/example/org-capture-ai

;;; Commentary:

;; This file provides a convenience function to initialize org-capture-ai
;; with Claude (Anthropic) as the LLM backend via gptel.
;;
;; Usage:
;;   (require 'org-capture-ai-claude)
;;   (org-capture-ai-init-claude "your-api-key-here")
;;
;; Or interactively:
;;   M-x org-capture-ai-init-claude
;;
;; Get your API key from: https://console.anthropic.com/

;;; Code:

;; Require gptel first - fail with clear message if not installed
(unless (require 'gptel nil t)
  (error "gptel package not installed. Run: M-x package-install RET gptel RET"))

;; Now require org-capture-ai
(unless (require 'org-capture-ai nil t)
  (error "org-capture-ai failed to load. Check that gptel is installed."))

;;;###autoload
(defun org-capture-ai-init-claude (api-key &optional model)
  "Initialize org-capture-ai with Claude/Anthropic backend.
API-KEY is your Anthropic API key (get it from https://console.anthropic.com/).
MODEL is the Claude model to use (defaults to claude-sonnet-4-5-20250929).

This configures gptel to use Claude and then sets up org-capture-ai.

Example usage:
  (org-capture-ai-init-claude \"sk-ant-...\")
  (org-capture-ai-init-claude \"sk-ant-...\" \"claude-sonnet-4-20250514\")"
  (interactive
   (list
    (read-string "Anthropic API Key: ")
    (let ((model-choice (completing-read
                         "Claude Model (default: claude-sonnet-4-5-20250929): "
                         '("claude-sonnet-4-5-20250929"
                           "claude-sonnet-4-20250514"
                           "claude-3-7-sonnet-20250219"
                           "claude-opus-4-1-20250805"
                           "claude-opus-4-20250514"
                           "claude-3-5-sonnet-20241022"
                           "claude-3-5-haiku-20241022"
                           "claude-3-opus-20240229")
                         nil nil nil nil "claude-sonnet-4-5-20250929")))
      (unless (string-empty-p model-choice)
        model-choice))))

  ;; Validate API key format
  (unless (and api-key (string-match-p "^sk-ant-" api-key))
    (user-error "Invalid API key format. Anthropic API keys start with 'sk-ant-'"))

  ;; Configure gptel for Anthropic/Claude
  (setq gptel-model (or model "claude-sonnet-4-5-20250929")
        gptel-backend (gptel-make-anthropic "Claude"
                        :stream t
                        :key api-key))

  (org-capture-ai--log "Configured gptel with Claude model: %s" gptel-model)
  (message "org-capture-ai: Configured to use Claude (%s)" gptel-model)

  ;; Now run the standard setup
  (org-capture-ai-setup))

(provide 'org-capture-ai-claude)
;;; org-capture-ai-claude.el ends here
