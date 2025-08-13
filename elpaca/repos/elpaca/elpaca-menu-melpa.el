;;; elpaca-menu-melpa.el --- Elpaca MELPA menu support -*- lexical-binding: t; -*-

;; Copyright (C) 2022-2025 Nicholas Vollmer

;; Author: Nicholas Vollmer
;; Keywords:

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

;;  MELPA support for Elpaca.

;;; Code:
(require 'cl-lib)
(require 'elpaca)
(require 'url)

(defvar elpaca-menu-melpa--index-cache
  (elpaca--read-file (expand-file-name "melpa.eld" elpaca-cache-directory))
  "MELPA recipe cache.")

(defvar url-http-end-of-headers)
(defun elpaca-menu-melpa--metadata ()
  "Return an alist of MELPA package metadata."
  (with-current-buffer (url-retrieve-synchronously "https://melpa.org/archive.json" 'silent)
    (let ((s (decode-coding-region url-http-end-of-headers (point-max) 'utf-8 t)))
      (if (fboundp #'json-parse-string)
          (json-parse-string s :object-type 'alist)
        (require 'json)
        (let ((json-object-type 'alist))
          (json-read-from-string s))))))

(defun elpaca-menu-melpa--clone (path)
  "Clone MELPA recipes repo to PATH."
  (let ((default-directory path))
    (make-directory path t)
    (make-directory (expand-file-name ".git/info/" path) t)
    (message "Downloading MELPA recipes...")
    (elpaca--with-no-git-config
     (let* ((processes
             (list
              (elpaca-process-call "git" "init")
              (elpaca-process-call "git" "config" "core.sparseCheckout" "true")
              (with-temp-buffer
                (insert "recipes")
                (append-to-file (point-min) (point-max)
                                (expand-file-name ".git/info/sparse-checkout" path)))
              (elpaca-process-call "git" "remote" "add" "origin" "https://github.com/melpa/melpa.git")
              (elpaca-process-call "git" "pull" "--depth=1" "origin" "master")
              (elpaca-process-call "git" "checkout" "master")
              (elpaca-process-call "git" "branch" "--set-upstream-to" "origin/master" "master")))
            (err (car (cl-remove-if #'zerop (delq nil processes) :key #'car))))
       (when err (error "Unable to clone MELPA: %S" err))
       (message "Downloading MELPA recipes...100%%")))))

(defun elpaca-menu-melpa--update ()
  "Update recipes in MELPA menu."
  (let ((default-directory (expand-file-name "melpa/" elpaca-cache-directory)))
    (message "Downloading MELPA...")
    (elpaca-with-process-call ("git" "pull")
      (message "%s" (if success "Downloading MELPA...100%%" stderr)))))

(defun elpaca-menu-melpa--convert (file metadata)
  "Return menu item candidate for FILE's MELPA recipe and METADATA."
  (with-current-buffer (get-buffer-create " elpaca-menu-melpa--convert")
    (insert-file-contents file nil nil nil 'replace)
    (condition-case-unless-debug _
        (when-let* ((recipe (read (buffer-string)))
                    (package (pop recipe))
                    ((member (plist-get recipe :fetcher)
                             '(git github gitlab sourcehut codeberg))))
          (setq recipe
                (append (list :package (symbol-name package)) recipe))
          (unless (plist-member recipe :files)
            (setq recipe (plist-put recipe :files elpaca-default-files-directive)))
          (let ((candidate (list :source "MELPA" :recipe recipe)))
            (when-let* ((data (alist-get package metadata)))
              (setq candidate
                    (append candidate
                            (list :description (alist-get 'desc data)
                                  :date
                                  (ignore-errors
                                    (when-let* ((s (number-to-string
                                                    (aref (alist-get 'ver data) 0))))
                                      (date-to-time
                                       (string-join (list
                                                     (substring s 0 4)
                                                     (substring s 4 6)
                                                     (substring s 6))
                                                    "-"))))
                                  :url (alist-get 'url (alist-get 'props data))))))
            (cons (intern-soft (file-name-nondirectory file)) candidate)))
      ((error) (message "elpaca-menu-melpa could not process %S" file) nil))))

(defun elpaca-menu-melpa--index (&optional item)
  "Return candidate list of available MELPA recipes.
If ITEM is non-nil, return that ITEM if found."
  (let ((miss-p nil))
    (setq elpaca-menu-melpa--index-cache
          (or elpaca-menu-melpa--index-cache
              (let* ((repo (expand-file-name "melpa/" elpaca-cache-directory))
                     (default-directory repo))
                (setq miss-p t)
                (unless (file-exists-p repo) (elpaca-menu-melpa--clone repo))
                (cl-loop with metadata = (elpaca-menu-melpa--metadata)
                         for file in (directory-files "./recipes/" 'full "\\(?:\\`[^.]\\)")
                         for candidate = (elpaca-menu-melpa--convert file metadata)
                         when candidate collect candidate))))
    (when miss-p (elpaca--write-file (expand-file-name "melpa.eld" elpaca-cache-directory)
                   (prin1 elpaca-menu-melpa--index-cache))))
  (if item (elpaca-alist-get item elpaca-menu-melpa--index-cache) elpaca-menu-melpa--index-cache))

;;;###autoload
(defun elpaca-menu-melpa (request &optional item)
  "Delegate ITEM REQUEST.
If REQUEST is `index`, return a recipe candidate alist.
If REQUEST is `update`, update the MELPA recipe cache."
  (pcase request
    ('index  (elpaca-menu-melpa--index item))
    ('update (setq elpaca-menu-melpa--index-cache nil)
             (when (file-exists-p (expand-file-name "melpa/" elpaca-cache-directory))
               (elpaca-menu-melpa--update))
             (elpaca-menu-melpa 'index item))))

(provide 'elpaca-menu-melpa)
;;; elpaca-menu-melpa.el ends here
