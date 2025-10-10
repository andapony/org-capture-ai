;;; setup.el --- Basic setup for org-capture-ai with Claude -*- lexical-binding: t; -*-

;;; Commentary:
;; Minimal configuration to get started with org-capture-ai using Claude.
;; Load this file or copy these commands to your init.el.

;;; Code:

;;; 1. Install required packages
;; Run these commands if packages aren't already installed:
;; M-x package-install RET gptel RET

;;; 2. Load org-capture-ai with Claude support

;; Check if gptel is installed
(unless (require 'gptel nil t)
  (error "ERROR: gptel is not installed.\n\nInstall it with:\n  M-x package-refresh-contents RET\n  M-x package-install RET gptel RET\n\nThen reload this file."))

;; Load org-capture-ai from the current directory
(add-to-list 'load-path "~/Sync/claude/bm")
(require 'org-capture-ai-claude)

;;; 3. Configure basic settings

;; Set where bookmarks will be saved
(setq org-capture-ai-default-file "~/bookmarks.org")
(setq org-capture-ai-summary-sentences 3)
(setq org-capture-ai-tag-count 5)

;;; 4. Initialize with Claude

;; Option 1: Use auth-source (recommended - secure)
;; Add this line to ~/.authinfo or ~/.authinfo.gpg:n
;; machine api.anthropic.com login apikey password sk-ant-YOUR-API-KEY
(org-capture-ai-init-claude
 (auth-source-pick-first-password :host "api.anthropic.com"))

;; Option 2: Set API key directly (less secure)
;; Uncomment and replace with your actual API key:
;; (org-capture-ai-init-claude "sk-ant-YOUR-API-KEY-HERE")

;; Option 3: Run interactively
;; M-x org-capture-ai-init-claude

;;; 5. Optional: Add keybindings

;; (global-set-key (kbd "C-c w") 'org-capture)
;; (with-eval-after-load 'org
;;   (define-key org-mode-map (kbd "C-c C-x r") 'org-capture-ai-reprocess-entry)
;;   (define-key org-mode-map (kbd "C-c C-x R") 'org-capture-ai-refresh-entry))

;;; 6. Test the setup

;; Run: M-x org-capture, select "u" for URL capture
;; Enter a URL - it will automatically finalize and process
;; The file will auto-save when processing completes

(provide 'setup)
;;; setup.el ends here
