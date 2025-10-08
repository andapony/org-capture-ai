;;; test-dublin-core-standalone.el --- Standalone test for Dublin Core extraction

;; Load just the needed functions
(require 'dom)
(require 'url)

;; Copy the relevant functions from org-capture-ai.el
(defun org-capture-ai-parse-html (html-string)
  "Parse HTML-STRING and return DOM tree."
  (with-temp-buffer
    (insert html-string)
    (libxml-parse-html-region (point-min) (point-max))))

(defun org-capture-ai--get-meta-tag (dom name)
  "Get content attribute from meta tag with NAME in DOM."
  (or (when-let ((meta-node
                  (car (dom-search dom
                         (lambda (node)
                           (and (eq (dom-tag node) 'meta)
                                (or (equal (dom-attr node 'name) name)
                                    (equal (dom-attr node 'property) name))))))))
        (string-trim (or (dom-attr meta-node 'content) "")))
      nil))

(defun org-capture-ai--extract-author (dom)
  "Extract author/creator from DOM."
  (or (org-capture-ai--get-meta-tag dom "DC.creator")
      (org-capture-ai--get-meta-tag dom "author")))

(defun org-capture-ai--extract-date (dom)
  "Extract publication date from DOM."
  (or (org-capture-ai--get-meta-tag dom "DC.date")
      (org-capture-ai--get-meta-tag dom "article:published_time")))

(defun org-capture-ai-extract-metadata (html url)
  "Extract Dublin Core metadata from HTML and URL."
  (let* ((dom (org-capture-ai-parse-html html))
         (parsed-url (url-generic-parse-url url))
         (host (url-host parsed-url)))
    (list
     :title (or (org-capture-ai--get-meta-tag dom "DC.title")
                (when-let ((title-node (car (dom-by-tag dom 'title))))
                  (string-trim (dom-texts title-node)))
                "Untitled")
     :description (or (org-capture-ai--get-meta-tag dom "DC.description")
                     (org-capture-ai--get-meta-tag dom "description")
                     "")
     :creator (org-capture-ai--extract-author dom)
     :publisher (or (org-capture-ai--get-meta-tag dom "DC.publisher")
                   (org-capture-ai--get-meta-tag dom "og:site_name")
                   host)
     :date (org-capture-ai--extract-date dom)
     :type (or (org-capture-ai--get-meta-tag dom "DC.type")
              "Text")
     :language (or (org-capture-ai--get-meta-tag dom "DC.language")
                  (dom-attr (car (dom-by-tag dom 'html)) 'lang)
                  "en")
     :rights (org-capture-ai--get-meta-tag dom "DC.rights")
     :identifier url
     :format "text/html")))

(message "\n=== Testing Dublin Core Metadata Extraction ===\n")

;; Test HTML
(defvar test-html "<!DOCTYPE html>
<html lang=\"en\">
<head>
    <title>Test Article Title</title>
    <meta name=\"author\" content=\"Jane Smith\">
    <meta name=\"description\" content=\"A comprehensive guide to testing.\">
    <meta name=\"DC.creator\" content=\"Jane Smith (Override)\">
    <meta name=\"DC.publisher\" content=\"Tech Publishing Inc\">
    <meta name=\"DC.date\" content=\"2025-10-01\">
    <meta name=\"DC.type\" content=\"Article\">
    <meta name=\"DC.rights\" content=\"CC BY-SA 4.0\">
</head>
<body>
    <article><h1>Test Article</h1></article>
</body>
</html>")

(let* ((url "https://example.com/test-article")
       (metadata (org-capture-ai-extract-metadata test-html url)))

  (message "TITLE: %s" (plist-get metadata :title))
  (message "DESCRIPTION: %s" (plist-get metadata :description))
  (message "CREATOR: %s" (plist-get metadata :creator))
  (message "PUBLISHER: %s" (plist-get metadata :publisher))
  (message "DATE: %s" (plist-get metadata :date))
  (message "TYPE: %s" (plist-get metadata :type))
  (message "LANGUAGE: %s" (plist-get metadata :language))
  (message "RIGHTS: %s" (plist-get metadata :rights))
  (message "IDENTIFIER: %s" (plist-get metadata :identifier))
  (message "FORMAT: %s" (plist-get metadata :format))

  (message "\n=== Tests ===")
  (message "✓ Title: %s" (if (equal (plist-get metadata :title) "Test Article Title") "PASS" "FAIL"))
  (message "✓ Creator (DC override): %s" (if (equal (plist-get metadata :creator) "Jane Smith (Override)") "PASS" "FAIL"))
  (message "✓ Publisher: %s" (if (equal (plist-get metadata :publisher) "Tech Publishing Inc") "PASS" "FAIL"))
  (message "✓ Date: %s" (if (equal (plist-get metadata :date) "2025-10-01") "PASS" "FAIL"))
  (message "✓ Type: %s" (if (equal (plist-get metadata :type) "Article") "PASS" "FAIL"))
  (message "✓ Language: %s" (if (equal (plist-get metadata :language) "en") "PASS" "FAIL"))
  (message "✓ Rights: %s" (if (equal (plist-get metadata :rights) "CC BY-SA 4.0") "PASS" "FAIL")))

(message "\n=== Dublin Core Test Complete ===")
