;;; flymake-zizmor.el --- Flymake backend for zizmor, a Github Actions static analyzer -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Kevin Brubeck Unhammer

;; Author: Kevin Brubeck Unhammer <unhammer@fsfe.org>
;; Keywords: convenience, languages
;; URL: https://github.com/unhammer/flymake-zizmor
;; Version: 0.0.1
;; Package-Requires: ((emacs "28.1"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This package provides flymake backend for zizmor, a Github Actions
;; static analyzer.  To use it, add the following to your init file:
;;
;;   (add-hook 'yaml-ts-mode-hook #'flymake-zizmor-setup)
;;
;; See https://zizmor.sh/ for how to install zizmor.
;;
;; As an alternative, there is also a lsp mode in the works:
;; https://github.com/zizmorcore/zizmor/issues/516

;;; Code:

(require 'flymake)

(defvar-local flymake-zizmor--proc nil)

(defgroup flymake-zizmor nil
  "Flymake backend for zizmor."
  :prefix "flymake-zizmor-"
  :group 'flymake)


(defcustom flymake-zizmor-program "zizmor"
  "A zizmor program name."
  :type 'string
  :group 'flymake-zizmor)

(defun flymake-zizmor (report-fn &rest _args)
  "Flymake backend for zizmor.

REPORT-FN is Flymake's callback function."
  (unless (executable-find flymake-zizmor-program)
    (error "Cannot find a suitable zizmor"))
  (when (process-live-p flymake-zizmor--proc)
    (kill-process flymake-zizmor--proc))
  (let ((source (current-buffer)))
    (save-restriction
      (widen)
      (setq flymake-zizmor--proc
            (make-process
             :name "flymake-zizmor" :noquery t :connection-type 'pipe
             :buffer (generate-new-buffer " *flymake-zizmor*")
             :command `(,flymake-zizmor-program "--format=github" ,(buffer-file-name))
             :sentinel
             (lambda (proc event) (flymake-zizmor--process-sentinel proc event source report-fn))))
      (process-send-region flymake-zizmor--proc (point-min) (point-max))
      (process-send-eof flymake-zizmor--proc))))

(defun flymake-zizmor--process-sentinel (proc _event source report-fn)
  "Sentinel of the `flymake-zizmor' process PROC for buffer SOURCE.

REPORT-FN is Flymake's callback function."
  (when (eq 'exit (process-status proc))
    (unwind-protect
        (if (with-current-buffer source (eq proc flymake-zizmor--proc))
            (with-current-buffer (process-buffer proc)
              (goto-char (point-min))
              (funcall report-fn (flymake-zizmor--collect-diagnostics source)))
          (flymake-log :warning "Canceling obsolete check %s" proc))
      (kill-buffer (process-buffer proc)))))

(defun flymake-zizmor--collect-diagnostics (source)
  "Collect diagnostics for buffer SOURCE from zizmor output in current buffer."
  (let (diags)
    (while (not (eobp))
      (cond
       ;; Example output:
       ;; ::warning file=.github/workflows/foo.yml,line=30,title=artipacked::foo.yml:30: credential persistence through GitHub Actions artifacts: does not set persist-credentials: false
       ((looking-at "^::\\(\\S +\\) +file=[^,\n]+,line=\\([0-9]+\\),title=\\([^: ]+\\)::[^ \n]+ +\\(.*\\)")
        (pcase-let ((`(,beg . ,end) (flymake-diag-region source (string-to-number (match-string 2)))))
          (push (flymake-make-diagnostic source ; locus
                                         beg
                                         end
                                         ;; type
                                         (if (equal (match-string 1) "warning")
                                             :warning
                                           (if (equal (match-string 1) "error")
                                               :error
                                             :note))
                                         (list               ; info
                                          "zizmor"           ; origin
                                          (match-string 3)   ; code
                                          (match-string 4))) ; message
                diags))))
      (forward-line 1))
    diags))

;;;###autoload
(defun flymake-zizmor-setup ()
  "Setup Flymake to use `flymake-zizmor' buffer locally."
  (add-hook 'flymake-diagnostic-functions #'flymake-zizmor nil t))


(provide 'flymake-zizmor)
;;; flymake-zizmor.el ends here
