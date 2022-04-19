;; -*- lexical-binding:t -*-

(When "^I minibuffer press \"\\(.+\\)\"$"
  (lambda (keybinding)
    (switch-to-buffer " *Minibuf-1*")
    (When (format "I press \"%s\"" keybinding))))

(When "^save on exit$"
  (lambda ()
    (let ((hook (lambda () (ignore-errors (ein:jupyter-server-stop)))))
      (cl-assert (member hook kill-emacs-hook))
      (let (asked-p
            confirm-kill-emacs
            confirm-kill-processes
            (kill-emacs-query-functions
             (list (lambda () (prog1 nil (funcall hook))))))
        (cl-letf (((symbol-function 'ein:jupyter-my-url-or-port)
                   #'ignore)
                  ((symbol-function 'y-or-n-p)
                   (lambda (prompt &rest _args)
                     (setq asked-p (or asked-p (string-match-p "save" prompt)))
                     nil)))
          (And "I press \"C-x C-c\"")
          (cl-assert asked-p))))))

(When "^I insert percent sign$" ;; https://github.com/ecukes/ecukes/issues/58
  (lambda ()
    (insert-char 37)))

(When "^I type session port \\([0-9]+\\)$"
  (lambda (port)
    (ein:process-refresh-processes)
    (cl-assert (not (ein:process-url-match (ein:url port))))
    (When (format "I type \"ein :session localhost:%s :results raw drawer\"" port))))

(When "^I ctrl-c-ctrl-c$"
  (lambda ()
    (cl-letf (((symbol-function 'read-directory-name)
               (lambda (&rest _args) ein:testing-jupyter-server-root)))
      (When "I press \"C-c C-c\""))))

(When "^with no opened notebooks call \"\\(.+\\)\"$"
  (lambda (func)
    (cl-letf (((symbol-function 'ein:notebook-opened-buffer-names) #'ignore))
      (When (format "I call \"%s\"" func)))))

(When "^header \\(does not \\)?says? \"\\(.+\\)\"$"
  (lambda (negate says)
    (let ((equal-p (string= (substitute-command-keys says)
                            (substitute-command-keys
                             (slot-value
                              (slot-value ein:%notification% 'kernel)
                              'message)))))
      (if negate (cl-assert (not equal-p)) (cl-assert equal-p)))))

(When "^I switch kernel to \"\\(.+\\)\"$"
  (lambda (kernel-name)
    (cl-letf (((symbol-function 'R-mode) #'ignore))
      (let ((notebook (ein:notebook-switch-kernel (ein:get-notebook) kernel-name)))
        (cl-loop repeat 10
                 until (ein:kernel-live-p (ein:$notebook-kernel notebook))
                 do (sleep-for 0 500)
                 finally do (cl-assert (string= "R" (ein:$kernelspec-language
                                                     (ein:$notebook-kernelspec notebook)))))))))

(When "^I kill kernel$"
  (lambda ()
    (ein:kernel-delete-session nil :kernel (ein:$notebook-kernel ein:%notebook%))
    (And "I wait for the smoke to clear")))

(When "^my reconnect is questioned"
  (lambda ()
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest ignore) t)))
      (ein:kernel-reconnect-session (ein:$notebook-kernel ein:%notebook%)
                                    (lambda (kernel session-p)
                                      (cl-assert (not session-p)))))))
(When "^I cannot save upon quit$"
  (lambda ()
    (let ((always-errback
           (lambda (args)
             (cl-destructuring-bind (notebook callback cbargs errback)
                 args
               (list notebook errback nil errback)))))
      (add-function :filter-args (symbol-function 'ein:notebook-save-notebook)
                    always-errback)
      (cl-letf (((symbol-function 'y-or-n-p)
                 (lambda (prompt) (message "%s" prompt) t)))
        (cl-assert (ein:notebook-opened-notebooks))
        (ein:notebook-close-notebooks)
        (Then "I should see message \"Some notebooks could not be saved.  Exit anyway?\""))
      (remove-function (symbol-function 'ein:notebook-save-notebook) always-errback))))

(When "I restart kernel$"
  (lambda ()
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest ignore) t)))
      (ein:notebook-restart-session-command))
    (And "I wait for the smoke to clear")))

(When "I kill processes like \"\\(.+\\)\"$"
  (lambda (substr)
    (mapc (lambda (p) (if (cl-search substr (process-name p)) (delete-process p)))
          (process-list))))

(When "^I clear websocket log$"
  (lambda ()
    (let ((buffer (cl-some (lambda (x) (and (cl-search "*websocket" x) x))
                           (mapcar #'buffer-name (buffer-list)))))
      (with-current-buffer buffer
        (let ((inhibit-read-only t))
          (erase-buffer))))))

(When "^I kill all websocket buffers$"
  (lambda ()
    (dolist (b (buffer-list))
      (when (cl-search "*websocket" (buffer-name b))
        (kill-buffer b)))))

(When "^no completion traffic"
  (lambda ()
    (let ((buffer (cl-some (lambda (x) (and (cl-search "*websocket" x) x))
                           (mapcar #'buffer-name (buffer-list)))))
      (with-current-buffer buffer
        (cl-assert (not (cl-search "\"matches\"" (buffer-string))))))))

(When "^I clear log expr \"\\(.+\\)\"$"
  (lambda (log-expr)
    (let ((buffer (get-buffer (symbol-value (intern log-expr)))))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (let ((inhibit-read-only t)
                (buffer-undo-list t))
            (erase-buffer)))))))

(When "^I switch to log expr \"\\(.+\\)\"$"
  (lambda (log-expr)
    (switch-to-buffer (symbol-value (intern log-expr)))))

(When "^no notebooks pending$"
  (lambda ()
    (cl-loop repeat 10
             until (zerop (hash-table-count *ein:notebook--pending-query*))
             do (sleep-for 0 500)
             finally do (cl-assert (zerop (hash-table-count *ein:notebook--pending-query*))))
    (with-current-buffer ein:log-all-buffer-name
      (And "I wait for buffer to say \"ein:query-sessions--complete\""))))

(When "^I wait for buffer process$"
  (lambda ()
    (ein:testing-wait-until (lambda () (get-buffer-process (current-buffer))))))

(When "^I possibly wait for gat install$"
  (lambda ()
    (unless (executable-find "gat")
      (When "I switch to buffer like \"*gat-install*\"")
      (ein:testing-wait-until (lambda () (not (get-buffer-process (current-buffer))))
                              nil 500000 5000))))

(When "^I switch to buffer like \"\\(.+\\)\"$"
  (lambda (substr)
    (cl-loop repeat 10
             for buf = (seq-some (lambda (b)
                                   (and (cl-search substr (buffer-name b)) b))
                                 (buffer-list))
             until (buffer-live-p buf)
             do (sleep-for 0 500)
             finally do (progn (cl-assert (buffer-live-p buf))
                               (switch-to-buffer buf)))))

(When "^rename notebook to \"\\(.+\\)\" succeeds$"
  (lambda (new-name)
    (let* ((old-name (ein:$notebook-notebook-name ein:%notebook%))
           (old-count
            (length (seq-filter (lambda (b)
                                  (cl-search old-name (buffer-name b)))
                                (buffer-list)))))
      (ein:notebook-rename-command new-name)
      (ein:testing-wait-until
       (lambda ()
         (= old-count
            (length (seq-filter (lambda (b)
                                  (cl-search new-name (buffer-name b)))
                                (buffer-list)))))))))

(When "^I am in notebooklist buffer$"
  (lambda ()
    (switch-to-buffer
     (ein:notebooklist-get-buffer
      (let ((default-directory ein:testing-project-path))
        (ein:jupyter-my-url-or-port))))
    (ein:testing-wait-until (lambda () (eq major-mode 'ein:notebooklist-mode)))))

(When "^I wait \\([.0-9]+\\) seconds?$"
  (lambda (seconds)
    (sleep-for (string-to-number seconds))))

(When "^I am in log buffer$"
  (lambda ()
    (switch-to-buffer ein:log-all-buffer-name)))

(When "^I gat create \"\\(.+\\)\" in \"\\(.+\\)\"$"
  (lambda (branch repo)
    (let ((need-wait (not (executable-find "gat"))))
      (cl-letf (((symbol-function 'read-string) (lambda (&rest _args) branch)))
	(let ((default-directory (concat default-directory "features/" repo)))
          (call-interactively #'ein:gat-create)
          (when need-wait
            (cl-loop repeat 5
                     until (get-buffer-process "*gat-install*")
                     do (sleep-for 0 1000))
            (cl-loop repeat 100
                     until (not (get-buffer-process "*gat-install*"))
                     do (sleep-for 0 5000))))))))

(When "^I trust things$"
  (lambda ()
    (let ((trustee (concat (file-name-as-directory
                            ein:testing-jupyter-server-root)
                           ".ein.ipynb")))
      (ein:testing-wait-until (lambda ()
                                (file-exists-p trustee))
                              nil 10000 1000)
      (shell-command (format "jupyter trust %s" trustee)))))

(When "^new git repo \"\\(.+\\)\"$"
  (lambda (repo)
    (Given (format "remove git repo \"%s\"" repo))
    (let ((git-dir (concat default-directory "features/" repo)))
      (make-directory git-dir)
      (with-temp-buffer
        (shell-command (format "git init -q %s" git-dir))))))

(When "^remove git repo \"\\(.+\\)\"$"
  (lambda (repo)
    (let ((git-dir (concat default-directory "features/" repo)))
      (with-temp-buffer
        (message (format "rm -rf %s" git-dir))
        (shell-command (format "rm -rf %s" git-dir))))))

(When "^new \\(.+\\) notebook\\( in \".+\"\\)?\\(\\)$"
  (lambda (prefix path workaround)
    (let ((url-or-port (let ((default-directory ein:testing-project-path))
                         (ein:jupyter-my-url-or-port)))
          notebook)
      (with-current-buffer (ein:notebooklist-get-buffer url-or-port)
        (-when-let* ((kslist (mapcar #'car (ein:list-available-kernels url-or-port)))
                     (found (seq-some (lambda (x) (and (cl-search prefix x) x)) kslist))
                     (ks (ein:get-kernelspec url-or-port found)))
          (setq notebook
                (ein:testing-new-notebook
                 url-or-port ks nil
                 (when path (progn (string-match "\"\\([^\"]+\\)\"" path)
                                   (match-string 1 path)))))))
      (cl-assert notebook)
      (switch-to-buffer (ein:notebook-buffer notebook)))))

(When "^I kill buffer and reopen$"
  (lambda ()
    (let ((name (ein:$notebook-notebook-name ein:%notebook%)))
      (When "I press \"C-x k\"")
      (And (format "old notebook \"%s\"" name)))))

(When "^I \\(finally \\)?stop the server\\(\\)$"
  (lambda (final-p _workaround)
    (cancel-function-timers #'ein:notebooklist-reload)
    (cl-letf (((symbol-function 'y-or-n-p) #'ignore))
      (ein:jupyter-server-stop
       nil
       (let ((default-directory ein:testing-project-path))
         (ein:jupyter-my-url-or-port))))
    (cl-loop repeat 10
             with buffer = (get-buffer *ein:jupyter-server-buffer-name*)
             until (null (get-buffer-process buffer))
             do (sleep-for 0 1000)
             finally do (aif (get-buffer-process buffer) (delete-process it)))
    (condition-case err
        (ein:testing-wait-until (lambda ()
                                  (null (ein:notebooklist-keys)))
                                nil 10000 1000)
      (error (ein:log 'warn "Stopping server: orphaned %s" (ein:notebooklist-keys))
             (clrhash ein:notebooklist-map)))
    (unless final-p
      (When "I clear log expr \"ein:log-all-buffer-name\"")
      (When "I clear log expr \"*ein:jupyter-server-buffer-name*\""))
    (setq default-directory ein:testing-project-path)))

(When "^I login to jupyterhub$"
  (lambda ()
    (cl-assert
     (when-let ((hub (seq-find (apply-partially #'string-match-p (concat (file-name-as-directory "user") user-login-name))
                               (mapcar
                                (lambda (json)
                                  (cl-destructuring-bind (&key url &allow-other-keys)
                                      json
                                    (ein:url url)))
                                (ein:jupyter-crib-running-servers)))))
       (let (done-p)
         (ein:login hub (lambda () (setq done-p t)))
         (prog1 t
           (unwind-protect
               (ein:testing-wait-until (lambda () done-p) nil 20000 1000)
             (Given "I finally stop the server"))))))))

(When "^I start jupyterhub configured \"\\(.*\\)\"$"
  (lambda (config)
    (When "I stop the server")
    (cl-letf (((symbol-function 'read-no-blanks-input)
               (lambda (&rest _args) (user-login-name))))
      (with-temp-file ".ecukes-temp-config.py" (insert (s-replace "\\n" "\n" config)))
      (let ((ein:jupyter-server-args
             '("--no-db" "--config=.ecukes-temp-config.py")))
        (ein:jupyter-server-start (executable-find "jupyterhub") nil t)
        (with-current-buffer (get-buffer *ein:jupyter-server-buffer-name*)
          (And "I wait for buffer to say \"running at\"")))
      (let ((prev (length (ein:jupyter-crib-running-servers)))
            (url-or-port (ein:jupyter-my-url-or-port)))
        (ein:query-singleton-ajax
         (ein:url url-or-port "hub/login")
         :data `(("username" . ,user-login-name)
                 ("password" . ,user-login-name)))
        (ein:testing-wait-until
         (lambda () (> (length (ein:jupyter-crib-running-servers)) prev))
         nil 20000 1000)))))

(When "^newlined region should be \"\\(.*\\)\"$"
  (lambda (region)
    (cl-assert (string= (s-replace "\\n" "\n" region)
                        (buffer-substring-no-properties (region-beginning) (region-end))))))

(When "^I start \\(and login to \\)?the server configured \"\\(.*\\)\"$"
  (lambda (login config)
    (When "I stop the server")
    (if config
        (with-temp-file ".ecukes-temp-config.py" (insert (s-replace "\\n" "\n" config)))
      (with-temp-file ".ecukes-temp-config.py" (insert (s-replace "\\n" "\n" "c.NotebookApp.token=u''\n"))))
    (let ((ein:jupyter-server-args '("--no-browser" "--config=.ecukes-temp-config.py")))
      (ein:jupyter-server-start (executable-find ein:jupyter-server-command)
                                ein:testing-jupyter-server-root (not login))
      (with-current-buffer (get-buffer *ein:jupyter-server-buffer-name*)
        (And "I wait for buffer to say \"is running at:\"")))
    (when login
      (ein:testing-wait-until (lambda () (ein:notebooklist-list)) nil 20000 1000))))

(When "^I login erroneously to \\(.*\\)$"
  (lambda (port)
    (cl-letf (((symbol-function 'ein:notebooklist-ask-url-or-port)
               (lambda (&rest _args) (ein:url port)))
              ((symbol-function 'read-passwd)
               (lambda (&rest _args) "foo")))
      (with-demoted-errors "demoted: %s"
        (When "I call \"ein:notebooklist-login\"")
        (And "I wait for the smoke to clear")))))

(When "^I login with bad curl$"
  (lambda ()
    (let ((request-curl-options '("--no-such-option")))
      (cl-letf (((symbol-function 'ein:notebooklist-ask-url-or-port)
                 (lambda (&rest _args) (ein:url 55217)))
                ((symbol-function 'read-passwd)
                 (lambda (&rest _args) "foo")))
        (When "I call \"ein:notebooklist-login\"")
        (And "I wait for the smoke to clear")))))

(When "^I login if necessary$"
  (lambda ()
    (-when-let* ((url-or-port (ein:jupyter-my-url-or-port))
                 (token (ein:jupyter-crib-token url-or-port)))
      (cl-letf (((symbol-function 'ein:notebooklist-ask-url-or-port)
                 (lambda (&rest _args) url-or-port))
                ((symbol-function 'read-passwd)
                 (lambda (&rest _args) token)))
        (When "I call \"ein:notebooklist-login\"")
        (And "I wait for the smoke to clear")))))

(When "^I login disabling crib token$"
  (lambda ()
    (-when-let* ((url-or-port (ein:jupyter-my-url-or-port))
                 (token (ein:jupyter-crib-token url-or-port)))
      (cl-letf (((symbol-function 'ein:notebooklist-ask-url-or-port)
                 (lambda (&rest _args) url-or-port))
                ((symbol-function 'ein:crib-token)
                 (lambda (&rest _args) (list nil nil))))
        (When "I call \"ein:notebooklist-login\"")
        (And "I wait for the smoke to clear")))))

(When "^I login \\(forcing ping \\)?with password \"\\(.+\\)\"$"
  (lambda (no-crib password)
    (let* ((url-or-port (ein:jupyter-my-url-or-port))
           (token (ein:jupyter-crib-token url-or-port))
           (orig-crib (symbol-function 'ein:notebooklist-token-or-password)))
      (cl-letf (((symbol-function 'ein:notebooklist-ask-url-or-port)
                 (lambda (&rest _args) url-or-port))
                ((symbol-function 'read-passwd)
                 (lambda (&rest _args) password))
                ((symbol-function 'ein:notebooklist-token-or-password)
                 (if no-crib
                     #'ignore
                   orig-crib)))
        (When "I call \"ein:notebooklist-login\"")
        (And "I wait for the smoke to clear")))))

(When "^dump diagnostic"
  (lambda ()
    (let ((fill (- (length buffer-undo-list) (length ein:%which-cell%))))
      (message "Undo inspect diagnostic %s %s | %s"
               buffer-undo-list ein:%which-cell% fill))))

(When "^I add fake cursor to undo list$"
  (lambda ()
    (push '(apply deactivate-cursor-after-undo 20) buffer-undo-list)
    (push '(apply activate-cursor-for-undo 20) buffer-undo-list)))

(When "^eval \"\\(.*\\)\"$"
  (lambda (command)
    (eval (car (read-from-string command)))))

(When "^I wait for completions \"\\(.+\\)\"$"
  (lambda (key)
    (cl-loop repeat 10
             until (gethash key (ein:$kernel-oinfo-cache (ein:get-kernel)))
             do (sleep-for 0 500)
             finally do (cl-assert (gethash key (ein:$kernel-oinfo-cache (ein:get-kernel)))))))

(When "^I wait for the smoke to clear"
  (lambda ()
    (ein:testing-flush-queries)
    (And "I wait 1 second"))) ;; eldoc-documentation-function not flushing

(When "^I keep clicking \"\\(.+\\)\" until \"\\(.+\\)\"$"
  (lambda (go stop)
    (cl-loop repeat 10
             until (cl-search stop (buffer-string))
             do (And (format "I click on \"%s\"" go))
             do (sleep-for 0 1000)
             finally do (cl-assert (cl-search stop (buffer-string))))))

(When "^I click\\( without going top\\)? on\\( file\\)? \"\\(.+\\)\"$"
  (lambda (stay file word)
    ;; from espuds "go to word" without the '\\b's
    (unless stay
      (goto-char (point-min)))
    (cl-loop repeat 10
             for search = (re-search-forward (format "\\[%s\\]" word) nil t)
             until search
             do (sleep-for 0 1000)
             finally do (cl-assert search))
    (backward-char)
    (let ((was (widget-at)))
      (When "I press \"RET\"")
      (unless file
        (cl-loop until (and (> (length (buffer-string)) 0)
                            (not (equal was (widget-at))))
                 do (sleep-for 0 500))))))

(When "^I click on dir \"\\(.+\\)\"$"
  (lambda (dir)
    (When (format "I go to word \"%s\"" dir))
    (re-search-backward "Dir" nil t)
    (let ((was (widget-at)))
      (When "I press \"RET\"")
      (cl-loop until (not (equal was (widget-at)))
               do (sleep-for 0 500)))))

(When "^I click on dir \"\\(.+\\)\" until \"\\(.+\\)\"$"
  (lambda (dir stop)
    (cl-loop repeat 10
             until (cl-search stop (buffer-string))
             do (When (format "I go to word \"%s\"" dir))
             do (re-search-backward "Dir" nil t)
             do (let ((was (widget-at)))
                  (When "I press \"RET\"")
                  (cl-loop until (not (equal was (widget-at)))
                           do (sleep-for 0 500)))
             finally do (cl-assert (cl-search stop (buffer-string))))))

(When "^old notebook \"\\(.+\\)\"$"
  (lambda (path)
    (let (notebook
          (url-or-port (ein:jupyter-my-url-or-port)))
      (with-current-buffer (ein:notebooklist-get-buffer url-or-port)
        (cl-loop repeat 2
                 do (ein:notebook-open url-or-port path nil
                                       (lambda (nb _created) (setq notebook nb)))
                 until (aand notebook
                             (ein:$notebook-kernel notebook)
                             (ein:kernel-live-p it))
                 do (sleep-for 0 1000)))
      (switch-to-buffer (ein:notebook-buffer notebook)))))

(When "^I dump buffer"
  (lambda () (message "%s" (buffer-string))))

(When "^I wait for buffer to\\( not\\)? say \"\\(.+\\)\"$"
  (lambda (negate bogey)
    (ein:testing-wait-until
     (lambda ()
       (let ((says (s-contains? (s-replace "\\n" "\n" bogey) (buffer-string))))
         (awhen (if negate (not says) says) it)))
     nil 35000 2000)))

(When "^I wait to be in buffer like \"\\(.+\\)\"$"
  (lambda (substr)
    (cl-loop repeat 10
             until (cl-search substr (buffer-name))
             do (sleep-for 0 500)
             finally do (cl-assert (cl-search substr (buffer-name))))))

(When "^I wait for cell to execute$"
  (lambda ()
    (poly-ein-base
     (let* ((cell (ein:worksheet-get-current-cell :cell-p #'ein:codecell-p))
            (orig (when (slot-boundp cell 'input-prompt-number)
                    (slot-value cell 'input-prompt-number))))
       (call-interactively #'ein:worksheet-execute-cell)
       (ein:testing-wait-until
        (lambda ()
          (ein:aand (and (slot-boundp cell 'input-prompt-number)
                         (slot-value cell 'input-prompt-number))
                    (and (numberp it)
                         (not (equal orig it)))))
        nil 15000 1500)))))

(When "^I undo again$"
  (lambda ()
    (undo-more 1)))

(When "^I enable \"\\(.+\\)\"$"
  (lambda (flag-name)
    (set (intern flag-name) t)))

(When "^I disable \"\\(.+\\)\"$"
  (lambda (flag-name)
    (set (intern flag-name) nil)))

(When "^I undo demoting errors$"
  (lambda ()
    (with-demoted-errors "demoted: %s"
      (undo))))

(When "^I start bad jupyter path$"
  (lambda ()
    (condition-case err
        (let ((ein:jupyter-server-command "not-jupyter"))
          (cl-letf (((symbol-function 'read-file-name)
                     (lambda (&rest _args) ein:jupyter-server-command))
                    ((symbol-function 'read-string)
                     (lambda (&rest args)
                       (error "%s" (car args))))
                    ((symbol-function 'read-directory-name)
                     (lambda (&rest _args) ein:jupyter-default-notebook-directory)))
            (call-interactively #'ein:jupyter-server-start))
          ;; should err before getting here
          (cl-assert nil))
      (error (cl-assert (cl-search "Server command:" (error-message-string err)))))))

(When "^I create a directory \"\\(.+\\)\" with depth \\([0-9]+\\) and width \\([0-9]+\\)$"
  (lambda (dir depth width)
    (when (f-exists? dir)
      (f-delete dir t))
    (f-mkdir dir)
    (ein:testing-make-directory-level dir 1
                                      (string-to-number width)
                                      (string-to-number depth))
    (call-process-shell-command (format "find %s -print | xargs du" dir))))

(When "^\"\\(.+\\)\" should \\(not \\)?include \"\\(.+\\)\"$"
  (lambda (variable negate value)
    (let ((member-p (member value (symbol-value (intern variable)))))
      (if negate (cl-assert (not member-p)) (cl-assert member-p)))))

(When "^I customize \"\\(.+\\)\" to \"\\(.+\\)\"$"
  (lambda (variable value)
    (custom-set-variables `(,(intern variable) ,value t))))

(When "^I set \"\\(.+\\)\" to \"\\(.+\\)\"$"
  (lambda (variable value)
    (set (intern variable) value)))

(When "^I set \"\\(.+\\)\" to eval \"\\(.+\\)\"$"
  (lambda (variable value)
    (set (intern variable) (eval (car (read-from-string value))))))

(When "^I fset \"\\(.+\\)\" to \"\\(.+\\)\"$"
  (lambda (variable value)
    (fset (intern variable) (function value))))

(When "^the value of \"\\(.+\\)\" is \\(.+\\)$"
  (lambda (variable value)
    (cl-assert (equal (symbol-value (intern variable)) (symbol-value (intern value))))))

(When "^I get into notebook mode \"\\(.+\\)\" \"\\(.+\\)\"$"
  (lambda (notebook-dir file-path)
    (When "I stop the server")
    (When (format "I find file \"%s\"" (concat (file-name-as-directory notebook-dir) file-path)))
    (When "I press \"C-c C-z\"")
    (ein:testing-wait-until (lambda () (ein:notebooklist-list)) nil 20000 1000)))

(When "^I find file \"\\(.+\\)\"$"
  (lambda (file-name)
    (find-file file-name)
    (when (string= (file-name-extension file-name) "ipynb")
      (ein:ipynb-mode))))

(When "notebooklist-list-paths\\( does not\\)? contains? \"\\(.+\\)\"$"
  (lambda (negate file-name)
    (Given "I am in notebooklist buffer")
    (let* ((nbpath (ein:url
                    (let ((default-directory ein:testing-project-path))
                      (ein:jupyter-my-url-or-port))
                    file-name))
           (contains-p (member nbpath (ein:notebooklist-list-paths))))
      (cl-assert (if negate (not contains-p) contains-p)))))

(When "I open \\(notebook\\|file\\) \"\\(.+\\)\"$"
  (lambda (content-type file-name)
    (Given "I am in notebooklist buffer")
    (And "I clear log expr \"ein:log-all-buffer-name\"")
    (let ((nbpath (ein:url (ein:jupyter-my-url-or-port) file-name)))
      (cl-letf (((symbol-function 'ein:notebooklist-ask-path)
                 (lambda (&rest _args) nbpath)))
        (When (format "I press \"C-c C-%s\"" (if (string= content-type "file") "f" "o")))
        (And "I wait for the smoke to clear")
        (Given "I switch to log expr \"ein:log-all-buffer-name\"")
        (Then (format "I should see \"Opened %s %s\"" content-type file-name))))))

(When "I evaluate the python code \"\\(.+\\)\"$"
  (lambda (code-str)
    (ein:shared-output-eval-string nil code-str)))

(When "^text property at point includes \"\\(.+\\)\"$"
  (lambda (properties)
    (cl-assert (not
                (cl-mapcan (lambda (prop)
                             (not (get-text-property (point) (intern prop))))
                           (split-string properties ","))))))
