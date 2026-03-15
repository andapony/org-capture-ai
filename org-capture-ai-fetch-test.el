;;; org-capture-ai-fetch-test.el --- Real HTTP fetch tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for org-capture-ai-fetch-url-curl and org-capture-ai-fetch-url-builtin
;; using a real local HTTP server (Python http.server).
;;
;; These tests exercise the actual fetch implementations that the main test
;; suites skip via mocking.  Requires Python 3 on PATH.

;;; Code:

(require 'ert)
(require 'org-capture-ai)

;;; Server Helpers

(defvar org-capture-ai-fetch-test--server-process nil
  "Process handle for the local test HTTP server.")

(defvar org-capture-ai-fetch-test--server-port nil
  "Port the local test HTTP server is listening on.")

(defun org-capture-ai-fetch-test--find-free-port ()
  "Return a currently-free TCP port on localhost.
Opens a server socket on port 0 (OS assigns a free port), reads the
assigned port, then immediately closes the socket."
  (let* ((proc (make-network-process
                :name "org-capture-ai-port-probe"
                :server t
                :host "127.0.0.1"
                :service 0
                :family 'ipv4))
         (port (process-contact proc :service)))
    (delete-process proc)
    port))

(defun org-capture-ai-fetch-test--fixture-dir ()
  "Return the absolute path to the test-fixtures/html directory."
  (expand-file-name
   "test-fixtures/html"
   (file-name-directory (or load-file-name buffer-file-name default-directory))))

(defun org-capture-ai-fetch-test--start-server ()
  "Start a Python HTTP server serving test-fixtures/html on a free port.
Sets `org-capture-ai-fetch-test--server-port' and
`org-capture-ai-fetch-test--server-process'.  Waits up to 2 seconds
for the server to become ready."
  (let* ((port (org-capture-ai-fetch-test--find-free-port))
         (dir  (org-capture-ai-fetch-test--fixture-dir))
         (proc (start-process "org-capture-ai-test-server"
                              "*org-capture-ai-test-server*"
                              "python3" "-m" "http.server"
                              (number-to-string port)
                              "--directory" dir)))
    (setq org-capture-ai-fetch-test--server-process proc
          org-capture-ai-fetch-test--server-port    port)
    ;; Poll until the server accepts connections (up to 2 seconds)
    (let ((ready nil)
          (deadline (+ (float-time) 2.0)))
      (while (and (not ready) (< (float-time) deadline))
        (condition-case _
            (progn
              (delete-process
               (make-network-process
                :name "org-capture-ai-port-check"
                :host "127.0.0.1"
                :service port
                :family 'ipv4
                :nowait nil))
              (setq ready t))
          (error (sit-for 0.05))))
      (unless ready
        (error "Test HTTP server failed to start on port %d" port)))
    port))

(defun org-capture-ai-fetch-test--stop-server ()
  "Kill the local test HTTP server."
  (when (and org-capture-ai-fetch-test--server-process
             (process-live-p org-capture-ai-fetch-test--server-process))
    (kill-process org-capture-ai-fetch-test--server-process))
  (setq org-capture-ai-fetch-test--server-process nil
        org-capture-ai-fetch-test--server-port    nil))

(defmacro org-capture-ai-fetch-test--with-server (port-var &rest body)
  "Run BODY with a local HTTP server; bind PORT-VAR to the port number.
Ensures the server is stopped even if BODY signals an error."
  (declare (indent 1))
  `(let ((,port-var (org-capture-ai-fetch-test--start-server)))
     (unwind-protect
         (progn ,@body)
       (org-capture-ai-fetch-test--stop-server))))

(defun org-capture-ai-fetch-test--wait (condition-fn &optional timeout-secs)
  "Poll CONDITION-FN every 50 ms until it returns non-nil or TIMEOUT-SECS elapses.
Returns the non-nil value of CONDITION-FN, or nil on timeout.
Default timeout is 10 seconds."
  (let ((deadline (+ (float-time) (or timeout-secs 10.0)))
        (result nil))
    (while (and (not (setq result (funcall condition-fn)))
                (< (float-time) deadline))
      (accept-process-output nil 0.05))
    result))

;;; Tests — curl

(ert-deftest org-capture-ai-fetch-test-curl-success ()
  "curl fetch retrieves HTML content from a real local server."
  (org-capture-ai-fetch-test--with-server port
    (let (result error-msg)
      (org-capture-ai-fetch-url-curl
       (format "http://127.0.0.1:%d/normal-article.html" port)
       (lambda (html) (setq result html))
       (lambda (err)  (setq error-msg err)))
      (org-capture-ai-fetch-test--wait (lambda () (or result error-msg)))
      (should-not error-msg)
      (should result)
      (should (string-match-p "Understanding Emacs Buffers" result)))))

(ert-deftest org-capture-ai-fetch-test-curl-missing-file ()
  "curl fetch calls error callback for a 404 response.
Python http.server returns a 404 page body for missing files; curl
exits successfully (exit 0) but the content will be an HTML error page.
The error callback is NOT called — curl considers the transfer complete.
This test documents that behavior: callers must inspect content for errors."
  (org-capture-ai-fetch-test--with-server port
    (let (result error-msg)
      (org-capture-ai-fetch-url-curl
       (format "http://127.0.0.1:%d/does-not-exist.html" port)
       (lambda (html) (setq result html))
       (lambda (err)  (setq error-msg err)))
      (org-capture-ai-fetch-test--wait (lambda () (or result error-msg)))
      ;; curl exits 0 on 404 — success-cb fires with error page HTML
      (should result)
      (should (string-match-p "404" result)))))

(ert-deftest org-capture-ai-fetch-test-curl-connection-refused ()
  "curl fetch calls error callback when connection is refused."
  ;; Use a port that nothing is listening on
  (let* ((port (org-capture-ai-fetch-test--find-free-port))
         result error-msg)
    (org-capture-ai-fetch-url-curl
     (format "http://127.0.0.1:%d/any.html" port)
     (lambda (html) (setq result html))
     (lambda (err)  (setq error-msg err)))
    (org-capture-ai-fetch-test--wait (lambda () (or result error-msg)))
    (should-not result)
    (should error-msg)))

;;; Tests — builtin

(ert-deftest org-capture-ai-fetch-test-builtin-success ()
  "url-retrieve fetch retrieves HTML content from a real local server."
  (org-capture-ai-fetch-test--with-server port
    (let (result error-msg)
      (org-capture-ai-fetch-url-builtin
       (format "http://127.0.0.1:%d/normal-article.html" port)
       (lambda (html) (setq result html))
       (lambda (err)  (setq error-msg err)))
      (org-capture-ai-fetch-test--wait (lambda () (or result error-msg)))
      (should-not error-msg)
      (should result)
      (should (string-match-p "Understanding Emacs Buffers" result)))))

(ert-deftest org-capture-ai-fetch-test-builtin-connection-refused ()
  "url-retrieve fetch calls error callback when connection is refused."
  (let* ((port (org-capture-ai-fetch-test--find-free-port))
         result error-msg)
    (org-capture-ai-fetch-url-builtin
     (format "http://127.0.0.1:%d/any.html" port)
     (lambda (html) (setq result html))
     (lambda (err)  (setq error-msg err)))
    (org-capture-ai-fetch-test--wait (lambda () (or result error-msg)))
    (should-not result)
    (should error-msg)))

;;; Tests — dispatch

(ert-deftest org-capture-ai-fetch-test-dispatch-curl ()
  "org-capture-ai-fetch-url dispatches to curl when fetch-method is curl."
  (org-capture-ai-fetch-test--with-server port
    (let ((org-capture-ai-fetch-method 'curl)
          result error-msg)
      (org-capture-ai-fetch-url
       (format "http://127.0.0.1:%d/normal-article.html" port)
       (lambda (html) (setq result html))
       (lambda (err)  (setq error-msg err)))
      (org-capture-ai-fetch-test--wait (lambda () (or result error-msg)))
      (should-not error-msg)
      (should (string-match-p "Emacs" result)))))

(ert-deftest org-capture-ai-fetch-test-dispatch-builtin ()
  "org-capture-ai-fetch-url dispatches to builtin when fetch-method is url-retrieve."
  (org-capture-ai-fetch-test--with-server port
    (let ((org-capture-ai-fetch-method 'url-retrieve)
          result error-msg)
      (org-capture-ai-fetch-url
       (format "http://127.0.0.1:%d/normal-article.html" port)
       (lambda (html) (setq result html))
       (lambda (err)  (setq error-msg err)))
      (org-capture-ai-fetch-test--wait (lambda () (or result error-msg)))
      (should-not error-msg)
      (should (string-match-p "Emacs" result)))))

(provide 'org-capture-ai-fetch-test)
;;; org-capture-ai-fetch-test.el ends here
