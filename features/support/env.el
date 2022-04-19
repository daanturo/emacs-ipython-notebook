;;; -*- lexical-binding: t; -*-
(require 'f)
(require 'espuds)
(require 'python)
(require 'julia-mode)
(require 'ess-r-mode)

(let* ((support-path (f-dirname load-file-name))
       (root-path (f-parent (f-parent support-path))))
  (add-to-list 'load-path (concat root-path "/lisp"))
  (add-to-list 'load-path (concat root-path "/test")))

(require 'ein-jupyter)
(require 'ein-dev)
(require 'ein-testing)
(require 'ein-ipynb-mode)
(require 'ein-file)
(require 'poly-ein)
(require 'ob-ein)
(require 'with-editor)
(require 'ein-markdown-mode)
(require 'paren)
(require 'ein-gat)

(when (>= emacs-major-version 27)
  (require 'org-tempo))

(unless with-editor-emacsclient-executable
  (!cons "gat" ecukes-exclude-tags))

(!cons "timestamp" ecukes-exclude-tags)

(unless (member "jupyterhub" ecukes-include-tags)
  (!cons "jupyterhub" ecukes-exclude-tags))

(when (getenv "GITHUB_ACTIONS")
  (cl-assert (not (eq system-type 'darwin)))
  (!cons "memory" ecukes-exclude-tags)
  (!cons "julia" ecukes-exclude-tags)
  (!cons "content" ecukes-exclude-tags)
  (!cons "svg" ecukes-exclude-tags)
  (!cons "gat" ecukes-exclude-tags)
  (!cons "pass" ecukes-exclude-tags) ;; salt?  stopped working around 20210316
  (!cons "switch" ecukes-exclude-tags))

(defalias 'activate-cursor-for-undo #'ignore)
(defalias 'deactivate-cursor-after-undo #'ignore)

(defvar ein:testing-jupyter-server-root (f-parent (f-dirname load-file-name)))

(defconst ein:testing-project-path (ecukes-project-path))

(defun ein:testing-after-scenario ()
  (let ((default-directory ein:testing-project-path))
    (with-current-buffer (ein:notebooklist-get-buffer (ein:jupyter-my-url-or-port))
      (cl-loop for notebook in (ein:notebook-opened-notebooks)
               for url-or-port = (ein:$notebook-url-or-port notebook)
               for path = (ein:$notebook-notebook-path notebook)
               for done-p = nil
               do (ein:notebook-kill-kernel-then-close-command
                   notebook (lambda (_kernel) (setq done-p t)))
               do (cl-loop repeat 16
                           until done-p
                           do (sleep-for 0 1000)
                           finally do (unless done-p
                                        (ein:display-warning (format "cannot close %s" path))))
               do (when (or (ob-ein-anonymous-p path)
                            (cl-search "Untitled" path)
                            (cl-search "Renamed" path))
                    (ein:notebooklist-delete-notebook ein:%notebooklist% url-or-port path)
                    (cl-loop with fullpath = (concat (file-name-as-directory ein:testing-jupyter-server-root) path)
                             repeat 10
                             for extant = (file-exists-p fullpath)
                             until (not extant)
                             do (sleep-for 0 1000)
                             finally do (when extant
                                          (ein:display-warning (format "cannot delete %s" path))))))))
  (awhen (ein:notebook-opened-notebooks)
    (cl-loop for nb in it
             for path = (ein:$notebook-notebook-path nb)
             do (ein:log 'debug "Notebook %s still open" path)
             finally do (cl-assert nil)))
  (cl-loop repeat 5
           for stragglers = (file-name-all-completions "Untitled"
                                                       ein:testing-jupyter-server-root)
           until (null stragglers)
           ;; do (message "ein:testing-after-scenario: fs stale handles: %s"
           ;;             (mapconcat #'identity stragglers ", "))
           do (sleep-for 0 1000))
  (mapc #'delete-file
        (mapcar (apply-partially #'concat
                                 (file-name-as-directory ein:testing-jupyter-server-root))
                (file-name-all-completions "Untitled" ein:testing-jupyter-server-root))))

(defmacro ein--remove-ecukes-io-advices (function class name)
  "The princ advice is known to peg CPU when cl-prin1 of nested objects."
  `(when (ad-find-advice ',function ',class ',name)
     (ad-remove-advice ',function ',class ',name)
     (ad-activate ',function)))

(Setup
 (ein--remove-ecukes-io-advices princ around princ-around)
 (ein--remove-ecukes-io-advices print around print-around)
 (ein:dev-start-debug)
 (setenv "GAT_APPLICATION_CREDENTIALS" "nonempty")
 (custom-set-variables '(python-indent-guess-indent-offset-verbose nil)
                       '(ein:jupyter-use-containers nil)
                       '(ein:gat-gce-zone "abc")
                       '(ein:gat-gce-region "abc")
                       '(ein:gat-aws-region "abc")
                       '(ein:gat-gce-project "abc")
                       '(electric-indent-mode nil)
                       '(ein:gat-machine-types '("abc"))
                       `(request-storage-directory ,(expand-file-name "test" ein:testing-project-path)))
 (setq ein:jupyter-default-kernel
       (cl-loop with cand = ""
             for (k . spec) in
             (alist-get
              'kernelspecs
              (let ((json-object-type 'alist))
                (json-read-from-string ;; intentionally not ein:json-read-from-string
                 (shell-command-to-string
                  (format "%s kernelspec list --json"
                          ein:jupyter-server-command)))))
             if (let ((lang (alist-get 'language (alist-get 'spec spec))))
                  (and (string= "python" lang)
                       (string> (symbol-name k) cand)))
             do (setq cand (symbol-name k))
             end
             finally return (intern cand)))
 (setq ein:testing-dump-file-log (concat default-directory "log/ecukes.log"))
 (setq ein:testing-dump-file-messages (concat default-directory "log/ecukes.messages"))
 (setq ein:testing-dump-file-server (concat default-directory "log/ecukes.server"))
 (setq ein:testing-dump-file-websocket (concat default-directory  "log/ecukes.websocket"))
 (setq ein:testing-dump-file-request  (concat default-directory "log/ecukes.request"))
 (setq org-confirm-babel-evaluate nil)
 (setq transient-mark-mode t)
 (Given "I start and login to the server configured \"\\n\""))

(Before
 (setq default-directory ein:testing-project-path))

(After
 (ein:testing-after-scenario))

(Teardown
 (Given "I finally stop the server"))

(Fail
 (if noninteractive
     (ein:testing-after-scenario)
   (keyboard-quit))) ;; useful to prevent emacs from quitting
