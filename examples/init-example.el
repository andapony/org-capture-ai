;;; init-example.el --- Example configuration for org-capture-ai -*- lexical-binding: t; -*-

;;; Commentary:
;; This file demonstrates various configuration options for org-capture-ai.
;; Copy relevant sections to your Emacs init file.

;;; Code:

;;; Basic Setup with OpenAI

;; Configure gptel for OpenAI
(use-package gptel
  :ensure t
  :custom
  (gptel-model 'gpt-4o)
  (gptel-api-key "your-openai-api-key-here"))  ; Or use auth-source

;; Configure org-capture-ai
(use-package org-capture-ai
  :load-path "~/path/to/org-capture-ai"
  :after (org-capture gptel)
  :custom
  (org-capture-ai-default-file "~/org/bookmarks.org")
  (org-capture-ai-summary-sentences 3)
  (org-capture-ai-tag-count 5)
  :config
  (org-capture-ai-setup))

;;; Advanced Setup with Anthropic Claude

;; Configure gptel for Claude
(use-package gptel
  :ensure t
  :custom
  (gptel-model 'claude-sonnet-4-5-20250929)
  :config
  (setq gptel-backend
        (gptel-make-anthropic "Claude"
          :stream t
          :key (lambda ()
                 (auth-source-pick-first-password
                  :host "api.anthropic.com")))))

;; Configure org-capture-ai with custom settings
(use-package org-capture-ai
  :load-path "~/path/to/org-capture-ai"
  :after (org-capture gptel)
  :custom
  (org-capture-ai-default-file "~/org/web-captures.org")
  (org-capture-ai-template-key "w")  ; Use "w" instead of "u"
  (org-capture-ai-summary-sentences 5)  ; Longer summaries
  (org-capture-ai-tag-count 7)
  (org-capture-ai-max-retries 5)
  (org-capture-ai-enable-logging t)
  (org-capture-ai-batch-idle-time 600)  ; 10 minutes
  :config
  (org-capture-ai-setup))

;;; Setup with Local Ollama

;; Configure gptel for local Ollama
(use-package gptel
  :ensure t
  :config
  (setq gptel-backend
        (gptel-make-ollama "Ollama"
          :host "localhost:11434"
          :stream t
          :models '(llama3.1:latest mistral:latest)))
  (setq gptel-model 'llama3.1:latest))

;; Configure org-capture-ai
(use-package org-capture-ai
  :load-path "~/path/to/org-capture-ai"
  :after (org-capture gptel)
  :custom
  (org-capture-ai-default-file "~/org/bookmarks.org")
  :config
  (org-capture-ai-setup))

;;; Queue-Based Processing (Don't Process Immediately)

(use-package org-capture-ai
  :load-path "~/path/to/org-capture-ai"
  :after (org-capture gptel)
  :custom
  (org-capture-ai-default-file "~/org/bookmarks.org")
  (org-capture-ai-process-on-capture nil)  ; Queue for later processing
  (org-capture-ai-batch-idle-time 300)  ; Process queue every 5 minutes when idle
  :config
  (org-capture-ai-setup))

;;; Using auth-source for API Keys

;; Add to ~/.authinfo or ~/.authinfo.gpg:
;; machine api.openai.com login apikey password YOUR-API-KEY
;; machine api.anthropic.com login apikey password YOUR-API-KEY

(use-package gptel
  :ensure t
  :config
  ;; For OpenAI
  (setq gptel-api-key
        (lambda ()
          (auth-source-pick-first-password :host "api.openai.com")))

  ;; Or for Anthropic
  (setq gptel-backend
        (gptel-make-anthropic "Claude"
          :stream t
          :key (lambda ()
                 (auth-source-pick-first-password
                  :host "api.anthropic.com")))))

;;; Custom Capture Templates

;; Define multiple capture templates for different purposes
(use-package org-capture-ai
  :load-path "~/path/to/org-capture-ai"
  :after (org-capture gptel)
  :config
  ;; Don't use default template
  (setq org-capture-ai-process-on-capture nil)

  ;; Add custom templates manually
  (add-to-list 'org-capture-templates
               '("w" "Web Article" entry
                 (file "~/org/articles.org")
                 "* %^{Title}
:PROPERTIES:
:URL: %^{URL}
:CAPTURED: %U
:STATUS: processing
:CATEGORY: article
:END:

%?"
                 :empty-lines 1
                 :after-finalize org-capture-ai--process-entry))

  (add-to-list 'org-capture-templates
               '("p" "Paper/Research" entry
                 (file "~/org/papers.org")
                 "* %^{Title}
:PROPERTIES:
:URL: %^{URL}
:CAPTURED: %U
:STATUS: processing
:TYPE: research
:AUTHORS: %^{Authors}
:END:

%?"
                 :empty-lines 1
                 :after-finalize org-capture-ai--process-entry))

  ;; Still need to add the hook
  (add-hook 'org-capture-after-finalize-hook
            #'org-capture-ai--process-entry))

;;; Keybindings

;; Add global keybinding for URL capture
(global-set-key (kbd "C-c w") 'org-capture)

;; Add keybindings for entry management
(with-eval-after-load 'org
  (define-key org-mode-map (kbd "C-c C-x r") 'org-capture-ai-reprocess-entry)
  (define-key org-mode-map (kbd "C-c C-x R") 'org-capture-ai-refresh-entry))

;; Add keybinding for batch processing
(global-set-key (kbd "C-c C-x p") 'org-capture-ai-process-queued)

;;; Integration with org-protocol

(require 'org-protocol)

(defun my/org-protocol-capture-url (info)
  "Capture URL from browser via org-protocol.
INFO contains :url and :title from the browser."
  (let* ((url (plist-get info :url))
         (title (plist-get info :title))
         (body (plist-get info :body)))
    ;; Create a capture entry directly
    (with-temp-buffer
      (org-mode)
      (insert "* " title "\n")
      (insert ":PROPERTIES:\n")
      (insert ":URL: " url "\n")
      (insert ":CAPTURED: " (format-time-string "[%Y-%m-%d %a %H:%M]") "\n")
      (insert ":STATUS: processing\n")
      (insert ":END:\n\n")
      (when body
        (insert "** Selected Text\n")
        (insert body "\n\n"))
      ;; Append to file
      (append-to-file (point-min) (point-max)
                      org-capture-ai-default-file))
    ;; Trigger async processing
    (run-with-timer 0.5 nil
      (lambda ()
        (with-current-buffer (find-file-noselect org-capture-ai-default-file)
          (goto-char (point-max))
          (org-back-to-heading)
          (org-capture-ai-reprocess-entry))))))

(add-to-list 'org-protocol-protocol-alist
             '("capture-url"
               :protocol "capture-url"
               :function my/org-protocol-capture-url))

;; Browser bookmarklet (one line):
;; javascript:location.href='org-protocol://capture-url?url='+encodeURIComponent(location.href)+'&title='+encodeURIComponent(document.title)+'&body='+encodeURIComponent(window.getSelection().toString())

;;; Hooks for Custom Processing

;; Add custom processing after AI analysis completes
(defun my/custom-post-processing ()
  "Custom processing after org-capture-ai completes."
  (when (and (derived-mode-p 'org-mode)
             (string= (org-entry-get nil "STATUS") "completed"))
    ;; Add to agenda if it's a high-priority topic
    (let ((tags (org-get-tags)))
      (when (or (member "important" tags)
                (member "research" tags))
        (org-todo "TODO")
        (org-priority ?A)))))

;; Hook could be added to org-after-todo-state-change-hook or similar

;;; Disable Automatic Processing (Manual Only)

(use-package org-capture-ai
  :load-path "~/path/to/org-capture-ai"
  :after (org-capture gptel)
  :custom
  (org-capture-ai-default-file "~/org/bookmarks.org")
  (org-capture-ai-process-on-capture nil)
  (org-capture-ai-batch-idle-time nil)  ; Disable batch processing
  :config
  ;; Don't call setup (don't add hooks)
  ;; Just load the library for manual use
  )

;; Then manually process entries with:
;; M-x org-capture-ai-reprocess-entry
;; M-x org-capture-ai-process-queued

;;; Multiple LLM Backends

;; Switch between backends based on task
(defvar my/gptel-backends
  (list (cons 'openai
              (gptel-make-openai "OpenAI"
                :key (lambda () (auth-source-pick-first-password
                                :host "api.openai.com"))))
        (cons 'claude
              (gptel-make-anthropic "Claude"
                :key (lambda () (auth-source-pick-first-password
                                :host "api.anthropic.com"))))
        (cons 'local
              (gptel-make-ollama "Ollama"
                :host "localhost:11434"
                :models '(llama3.1:latest)))))

(defun my/switch-llm-backend (backend-name)
  "Switch gptel backend to BACKEND-NAME."
  (interactive
   (list (intern (completing-read "Backend: "
                                  '("openai" "claude" "local")))))
  (setq gptel-backend (alist-get backend-name my/gptel-backends))
  (message "Switched to %s backend" backend-name))

(provide 'init-example)
;;; init-example.el ends here
