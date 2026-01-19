; -*- lexical-binding: t; -*-
;; disable gui elements
(menu-bar-mode -1)
(scroll-bar-mode -1)
(tool-bar-mode -1)
(global-display-line-numbers-mode)

(display-line-numbers-mode +1)

;; Show trailing whitespace only in programming and writing buffers
(add-hook 'prog-mode-hook (lambda () (setq show-trailing-whitespace t)))
(add-hook 'org-mode-hook (lambda () (setq show-trailing-whitespace t)))
(add-hook 'markdown-mode-hook (lambda () (setq show-trailing-whitespace t)))

;; Performance settings for lsp-mode
(setq gc-cons-threshold 100000000)
(setq read-process-output-max (* 1024 1024))

;; https://idiomdrottning.org/bad-emacs-defaults
(make-directory "~/.emacs_backups/" t)
(make-directory "~/.emacs_autosave/" t)
(setq auto-save-file-name-transforms '((".*" "~/.emacs_autosave/" t)))
(setq backup-directory-alist '(("." . "~/.emacs_backups/")))
(setq backup-by-copying t)

(setq require-final-newline t)


;; Fix packages not found when using tramp
(require 'tramp-sh)
(setq tramp-remote-path
      (append tramp-remote-path
 	       '(tramp-own-remote-path)))

;; Fix flycheck opening on the right
(add-to-list 'display-buffer-alist
             '("\\*Flycheck errors\\*"
               ;; Reuse an existing window or create a new one at the bottom:
               (display-buffer-reuse-window display-buffer-at-bottom)
               ;; Optionally set the desired height:
               (window-height . 0.3)))

(use-package bind-key
  :ensure t
  :config
  (add-to-list 'same-window-buffer-names "*Personal Keybindings*"))

;; git
(use-package magit
  :config
  (setq magit-define-global-key-bindings 'recommended))

;; tabs
(use-package all-the-icons
  :demand t)
(use-package centaur-tabs
  :demand
  :after (all-the-icons)
  :config
  (centaur-tabs-headline-match)
  (centaur-tabs-enable-buffer-reordering)
  (centaur-tabs-change-fonts "FiraCode" 120)
  (centaur-tabs-mode t)
  :custom
  (centaur-tabs-set-icons t)
  (centaur-tabs-height 30)
  (centaur-tabs-set-close-button nil)
  (centaur-tabs-style "bar")
  (centaur-tabs-show-new-tab-button nil)
  (centaur-tabs-set-bar 'under)
  ;; Note: If you're not using Spacmeacs, in order for the underline to display
  ;; correctly you must add the following line:
  (x-underline-at-descent-line t)
  :bind
  ("C-<prior>" . centaur-tabs-backward)
  ("C-<next>" . centaur-tabs-forward))

(use-package monet :ensure t)

;; for eat terminal backend:
(use-package eat :ensure t)

;; install claude-code.el
(use-package claude-code :ensure t
  :after (eat monet)
  :custom
  (claude-code-terminal-backend 'eat)
  :config
  (add-hook 'claude-code-process-environment-functions #'monet-start-server-function)
  (monet-mode 1)
  (claude-code-mode)
  :bind ("C-c c" . claude-code-transient))

;; chatgpt integration
(use-package f)
(use-package gptel
  :after (f)
  :bind
  ("C-c l" . gptel)
  :config
  (setq gptel-api-key (f-read-text "/run/secrets/emacs_oai_key" 'utf-8)))

;; mode line
(use-package moody
  :config
  (setq x-underline-at-descent-line t)
  (moody-replace-mode-line-buffer-identification)
  (moody-replace-vc-mode)
  (moody-replace-eldoc-minibuffer-message-function))

;; font
(set-frame-font "FiraCode 12" nil t)

;; vim keybinds
(use-package evil
  :demand t
  :init
  (setq evil-want-keybinding nil)
  :config
  (evil-mode 1))

(use-package evil-collection
  :after (evil)
  :config
  (evil-collection-init)
  ;; Remove org-agenda-mode from emacs state so evil keybindings work
  (setq evil-emacs-state-modes (delq 'org-agenda-mode evil-emacs-state-modes)))

;; theme
(use-package dracula-theme
  :config
  (load-theme 'dracula t))

;; required for lsp-mode
(use-package yasnippet)

;; search
(use-package rg
  :config
  (rg-enable-default-bindings))

;; lsp support
(use-package lsp-mode
  :hook
  (sh-mode . lsp-deferred)
  :custom
  (lsp-ruff-server-command '(ruff server --preview)))

(use-package lsp-ui
  :after (lsp-mode))

;; error checking
(use-package flycheck
  :init (global-flycheck-mode)
  :config
  (setq flycheck-idle-change-delay 1)
  (setq flycheck-check-syntax-automatically '(save idle-change)))


;; mindmap
(use-package htmlize)

(require 'ob-haskell)


(use-package org-roam
  :demand t
  :custom
  (org-roam-directory (file-truename "/home/collin/org/roam/"))
  (org-roam-completion-everywhere t)
  :bind (("C-c n l" . org-roam-buffer-toggle)
         ("C-c n f" . org-roam-node-find)
         ("C-c n g" . org-roam-graph)
         ("C-c n i" . org-roam-node-insert)
         ("C-c n c" . org-roam-capture)
         :map org-roam-dailies-map
         ("Y" . org-roam-dailies-capture-yesterday)
         ("T" . org-roam-dailies-capture-tomorrow))
  :bind-keymap
  ("C-c n d" . org-roam-dailies-map)
  :config
  (setq org-roam-dailies-directory "/home/collin/org/roam/")
  (setq my-publish-time 0)   ; see the next section for context
  (defun roam-publication-wrapper (plist filename pubdir)
    (org-html-publish-to-html plist filename pubdir)
    (setq my-publish-time (cadr (current-time))))
  (require 'seq)

  (defun filter-backlinks (ast)
    (cl-destructuring-bind (type &rest items) ast
      (cons type
            (seq-filter
             (lambda (it)
               (let* ((link (car it))
                      (file (when (and (stringp link)
                                       (string-match "\\[\\[file:\\([^][|]+\\)\\]" link))
                              (expand-file-name (match-string 1 link) org-roam-directory))))
		 (or (null file)
                     (not (seq-some
                           (lambda (n)
                             (and (string= (org-roam-node-file n) file)
                                  (org-roam-backlinks-get n)))
                           (org-roam-node-list))))))
             items))))
  (defun roam-sitemap (title list)
    (concat "#+OPTIONS: ^:nil author:nil html-postamble:nil\n"
            "#+SETUPFILE: ./simple_inline.theme\n"
            "#+TITLE: " title "\n\n"
            (org-list-to-org (filter-backlinks list))))
  (setq org-publish-project-alist
    `(("roam"
       :base-directory "~/org/roam/"
       :base-extension "org"
       :recursive t
       :auto-sitemap t
       :sitemap-function  roam-sitemap
       :stiemap-style list
       :sitemap-title     "Roam notes"
       :exclude "\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)\\.org"
       :publishing-function roam-publication-wrapper
       :publishing-directory "~/org/roam/site/"
       :exclude-tags ("noexport")
       :style "<link rel=\"stylesheet\" href=\"../other/mystyle.cs\" type=\"text/css\">")))
  (defun org-roam-custom-link-builder (node)
    (let ((file (org-roam-node-file node)))
      (concat (file-name-base file) ".html")))
  (setq org-roam-graph-link-builder 'org-roam-custom-link-builder)

  (setq org-confirm-babel-evaluate nil)
  (setq org-roam-capture-templates
	'(
	  ("d" "default" plain "%?"
	   :target (file+head "%<%Y%m%d%H%M%S>-${slug}.org"
			      "#+title: ${title}\n")
	   :unnarrowed t)
	  ("l"  ;; A key to trigger this template, e.g., "l" for "LeetCode".
           "LeetCode Problem"
           plain
           ;; The body of the capture template:
           ;; ------------------------------------------------------------
           "
	   * [[%^{LeetCode URL}][Problem %^{Problem Number}. %^{Problem Title}]]
	   ** Brute Force Solution
	   #+begin_src python
	   %?
	   #+end_src

	   *** Explanation
	   Describe your brute force approach here.

	   - Time Complexity:
	   - Space Complexity:

	   ** Optimal Solution

	   *** Algorithm Name:
	   (Explain the name of the algorithm if relevant, e.g., Boyer–Moore, Two-Pointer, etc.)

	   #+begin_src python
	   #+end_src

	   *** Explanation
	   Describe your optimal approach here.

	   - Time Complexity:
	   - Space Complexity:
	   "
           ;; ------------------------------------------------------------
           ;; Where to store the new note file:
           :if-new
           (file+head
            "leetcode/${slug}.org"          ;; Creates a file leetcode/your-problem-title.org
            "#+title: Problem %^{Problem Number}. %^{Problem Title}\n")
           :immediate-finish nil
           :jump-to-captured t)))
  ;; If you're using a vertical completion framework, you might want a more informative completion interface
  (setq org-roam-node-display-template (concat "${title:*} " (propertize "${tags:10}" 'face 'org-tag)))
  (org-roam-db-autosync-mode)

  (require 'org-roam-dailies) ;; Ensure the keymap is available
  (require 'org-roam-export)
  ;; If using org-roam-protocol
  (require 'org-roam-protocol))

(use-package org-journal
  :defer t
  :init
  ;; Change default prefix key; needs to be set before loading org-journal
  (setq org-journal-prefix-key "C-c j ")
  :config
  (setq org-journal-dir "~/org/journal/"
        org-journal-date-format "%A, %d %B %Y"))

(use-package hydra)
(use-package org-fc
  :custom
  (org-fc-directories '("/home/collin/org/"))
  :bind ("C-c f" . org-fc-hydra/body)
  :config
  (require 'org-fc-hydra)
  (require 'org-fc-keymap-hint)
  ;; Keybindings for org-fc-review-flip-mode
  (evil-define-minor-mode-key '(normal insert emacs) 'org-fc-review-flip-mode
    (kbd "RET") 'org-fc-review-flip
    (kbd "n") 'org-fc-review-flip
    (kbd "s") 'org-fc-review-suspend-card
    (kbd "q") 'org-fc-review-quit)

  ;; Keybindings for org-fc-review-rate-mode
  (evil-define-minor-mode-key '(normal insert emacs) 'org-fc-review-rate-mode
    (kbd "a") 'org-fc-review-rate-again
    (kbd "h") 'org-fc-review-rate-hard
    (kbd "g") 'org-fc-review-rate-good
    (kbd "e") 'org-fc-review-rate-easy
    (kbd "s") 'org-fc-review-suspend-card
    (kbd "q") 'org-fc-review-quit))


;; todo highlighting
;; (use-package hl-todo
;;   :config (setq hl-todo-keyword-faces '(("TODO"   . "#FFB86C"))))

;; (use-package flycheck-hl-todo
;;   :init
;;   (flycheck-hl-todo-setup))

;; text completion
(use-package company
  :config
  (setq company-idle-delay 0.2
	company-tooltip-limit 10
	company-minimum-prefix-length 2)
  (add-hook 'after-init-hook 'global-company-mode))

(use-package helm-lsp :commands helm-lsp-workspace-symbol)

(use-package which-key
  :config
  (which-key-mode))

;; json
(use-package json-mode
  :mode "\\.json\\'")

;; terraform
(use-package terraform-mode
  ;; if using straight
  ;; :straight t

  ;; if using package.el
  ;; :ensure t
  :custom (terraform-indent-level 4)
  :hook (terraform-mode . lsp-deferred))

;; scala
(use-package lsp-metals
  :custom
  ;; You might set metals server options via -J arguments. This might not always work, for instance when
  ;; metals is installed using nix. In this case you can use JAVA_TOOL_OPTIONS environment variable.
  (lsp-metals-server-args '(;; Metals claims to support range formatting by default but it supports range
                            ;; formatting of multiline strings only. You might want to disable it so that
                            ;; emacs can use indentation provided by scala-mode.
                            "-J-Dmetals.allow-multiline-string-formatting=off"
                            ;; Enable unicode icons. But be warned that emacs might not render unicode
                            ;; correctly in all cases.
                            "-J-Dmetals.icons=unicode"))
  ;; In case you want semantic highlighting. This also has to be enabled in lsp-mode using
  ;; `lsp-semantic-tokens-enable' variable. Also you might want to disable highlighting of modifiers
  ;; setting `lsp-semantic-tokens-apply-modifiers' to `nil' because metals sends `abstract' modifier
  ;; which is mapped to `keyword' face.
  (lsp-metals-enable-semantic-highlighting t)
  :hook (scala-mode . lsp-deferred))

(use-package scala-mode
  :interpreter ("scala" . scala-mode))

;; python
(use-package python-mode
  :mode "\\.py\\'")

(use-package lsp-pyright
  :ensure t
  :custom
  (lsp-pyright-langserver-command "pyright") ;; or basedpyright
  :hook (python-mode . (lambda ()
                         (require 'lsp-pyright)
                         (lsp-deferred))))  ; or lsp-deferred
(use-package python-pytest)

;; haskell
(use-package lsp-haskell
  :hook
  (haskell-mode . lsp-deferred)
  (haskell-literate-mode . lsp-deferred))

(use-package haskell-mode
  :config
  (setq haskell-indent-offset 2)
  :hook
  (haskell-mode . interactive-haskell-mode)
  :mode "\\.hs\\'")

(use-package reformatter)

(use-package ormolu
  :bind
  (:map haskell-mode-map
	("C-c r" . ormolu-format-buffer)))

;; tidal
(use-package tidal
  :config
  (setq tidal-interpreter "tidal")
  (setq tidal-boot-script-path "/nix/store/vb6a29270572fxwbm54dyj2wfgsxqiq7-source/BootTidal.hs" )
  :mode ("\\.tidal\\'" . tidal-mode))

;; nix
(use-package nix-mode
  :hook
  (nix-mode . lsp-deferred)
  :custom
  (lsp-nix-nil-auto-eval-inputs t)
  :config
  (setq nix-indent-offset 2)
  :mode ("\\.nix\\'" "\\.nix.in\\'"))
(use-package nix-drv-mode
  :ensure nix-mode
  :mode "\\.drv\\'")
(use-package nix-shell
  :ensure nix-mode
  :commands (nix-shell-unpack nix-shell-configure nix-shell-build))
(use-package nix-repl
  :ensure nix-mode
  :commands (nix-repl))

;; docker
(use-package dockerfile-mode)

;; minibuffer completion
(global-set-key (kbd "C-x C-f") #'helm-find-files)
(use-package helm
  :init
  (helm-mode 1))

;; dashboard
(use-package dashboard
  :config
  (dashboard-setup-startup-hook)
  :custom
  (dashboard-icon-type 'all-the-icons)
  (dashboard-set-heading-icons t)
  (dashboard-set-file-icons t)
  (dashboard-startup-banner
   (let ((hostname (system-name)))
     (pcase hostname
       ("ghoul" "/home/collin/brew/configurations/emacs/ghoul_dracula.png")
       ("arachne" "/home/collin/brew/configurations/emacs/arachne_dracula.png")
       ("azathoth" "/home/collin/brew/configurations/emacs/azathoth_dracula.png")
       (_ "/home/collin/brew/configurations/emacs/hydra.txt"))))
  (dashboard-projects-backend 'projectile)
  (dashboard-items '((recents  . 5)
			  (bookmarks . 5)
			  (projects . 10)))
  (dashboard-image-banner-max-height 512)
  (dashboard-center-content t))

;; project management
(use-package projectile
  :ensure t
  :custom
  (projectile-project-search-path '("~/projects/" "~/work_projects/"))
  :config
  (setq projectile-indexing-method 'alien)
  (define-key projectile-mode-map (kbd "C-c C-p") 'projectile-command-map)
  (global-set-key (kbd "C-c p") 'projectile-command-map)
  (projectile-mode +1)
  (projectile-discover-projects-in-search-path))

(use-package helm-projectile
  :after projectile
  :ensure t)

;; setup pinentry for gpg signing
(use-package pinentry)
(pinentry-start)

;; direnv intergration
(use-package envrc
  :hook
  (after-init . envrc-global-mode)
  :config
  (setq envrc-remote t)
  ;; 1.  All Babel execution that happens during export

  (advice-add #'org-babel-execute-src-block :around #'envrc-propagate-environment)
  (advice-add 'org-babel-exp-src-block :around #'envrc-propagate-environment)
  (advice-add 'org-export-as :around #'envrc-propagate-environment)
  (advice-add 'org-html-export-to-html :around #'envrc-propagate-environment)
  ;; 2.  Any direct compiler-detection that ob-haskell (or haskell-mode) does
;; Add this to your configuration
  (advice-add 'org-babel-execute:haskell :around #'envrc-propagate-environment)
  (advice-add 'org-babel-haskell-initiate-session :around #'envrc-propagate-environment)
  (advice-add 'org-babel-prep-session:haskell :around #'envrc-propagate-environment)
  (advice-add 'org-babel-haskell-evaluate :around #'envrc-propagate-environment)
  (advice-add 'org-babel-variable-assignments:haskell :around #'envrc-propagate-environment)
  (advice-add 'org-babel-expand-body:haskell :around #'envrc-propagate-environment)
  (advice-add 'org-babel-haskell--session-buffer :around #'envrc-propagate-environment)
  (advice-add 'org-babel-haskell--buffer-contents :around #'envrc-propagate-environment))


;; smart parenthesis
(use-package smartparens
  :config
  (require 'smartparens-config)
  (smartparens-global-mode t))

;; common lisp
(use-package slime
  :config
  (setq inferior-lisp-program "sbcl"
	slime-completion-at-point-functions 'slime-fuzzy-complete-symbol))

(use-package typescript-mode
  :mode
  "\\.tsx\\'"
  :hook
  (tsx-ts-mode . lsp-deffered)
  :custom
  (typescript-indent-level 2))

;; futhark
(use-package futhark-mode
  :mode
  "\\.fut\\'"
  :hook
  (furthark-mode . eglot-ensure))

;; go
(use-package go-mode
  :mode
  "\\.go\\'"
  :hook ((go-mode . lsp-deferred)))
;;(before-save . lsp-format-buffer)
;;(before-save . lsp-organize-imports))

;; org
(use-package org
  :bind
  ("C-c a" . org-agenda)
  :config
  (setq fill-column 80)
  (setq org-agenda-files '("~/org/roam/"))
  ;; TODO states matching taskwarrior workflow
  (setq org-todo-keywords
        '((sequence "TODO(t)" "ACTIVE(a)" "WAITING(w)" "|" "DONE(d)" "CANCELLED(c)")))
  :hook
  (org-mode . auto-fill-mode))

;; markdown
(use-package markdown-mode
  :config
  (setq fill-column 80)
  :hook
  (markdown-mode . auto-fill-mode)
  :mode ("README\\.md\\'" . gfm-mode)
  :init (setq markdown-command "pandoc"))

;; Spell checking
(use-package jinx
  :hook
  (org-mode . jinx-mode)
  (markdown-mode . jinx-mode))

;; Ligature support
(use-package ligature
  :config
  ;; Enable the "www" ligature in every possible major mode
  (ligature-set-ligatures 't '("www"))
  ;; Enable traditional ligature support in eww-mode, if the
  ;; `variable-pitch' face supports it
  (ligature-set-ligatures 'eww-mode '("ff" "fi" "ffi"))
  ;; Enable all Cascadia and Fira Code ligatures in programming modes
  (ligature-set-ligatures 'prog-mode
                          '(;; == === ==== => =| =>>=>=|=>==>> ==< =/=//=// =~
                            ;; =:= =!=
                            ("=" (rx (+ (or ">" "<" "|" "/" "~" ":" "!" "="))))
                            ;; ;; ;;;
                            (";" (rx (+ ";")))
			    ;; && &&&
			    ("&" (rx (+ "&")))
			    ;; !! !!! !. !: !!. != !== !~
			    ("!" (rx (+ (or "=" "!" "\." ":" "~"))))
			    ;; ?? ??? ?:  ?=  ?.
			    ("?" (rx (or ":" "=" "\." (+ "?"))))
			    ;; %% %%%
			    ("%" (rx (+ "%")))
			    ;; |> ||> |||> ||||> |] |} || ||| |-> ||-||
			    ;; |->>-||-<<-| |- |== ||=||
			    ;; |==>>==<<==<=>==//==/=!==:===>
			    ("|" (rx (+ (or ">" "<" "|" "/" ":" "!" "}" "\]"
					    "-" "=" ))))
			    ;; \\ \\\ \/
			    ("\\" (rx (or "/" (+ "\\"))))
			    ;; ++ +++ ++++ +>
			    ("+" (rx (or ">" (+ "+"))))
			    ;; :: ::: :::: :> :< := :// ::=
			    (":" (rx (or ">" "<" "=" "//" ":=" (+ ":"))))
			    ;; // /// //// /\ /* /> /===:===!=//===>>==>==/
			    ("/" (rx (+ (or ">"  "<" "|" "/" "\\" "\*" ":" "!"
					    "="))))
			    ;; .. ... .... .= .- .? ..= ..<
			    ("\." (rx (or "=" "-" "\?" "\.=" "\.<" (+ "\."))))
			    ;; -- --- ---- -~ -> ->> -| -|->-->>->--<<-|
			    ("-" (rx (+ (or ">" "<" "|" "~" "-"))))
			    ;; *> */ *)  ** *** ****
			    ("*" (rx (or ">" "/" ")" (+ "*"))))
			    ;; www wwww
			    ("w" (rx (+ "w")))
			    ;; <> <!-- <|> <: <~ <~> <~~ <+ <* <$ </  <+> <*>
			    ;; <$> </> <|  <||  <||| <|||| <- <-| <-<<-|-> <->>
			    ;; <<-> <= <=> <<==<<==>=|=>==/==//=!==:=>
			    ;; << <<< <<<<
			    ("<" (rx (+ (or "\+" "\*" "\$" "<" ">" ":" "~"  "!"
					    "-"  "/" "|" "="))))
			    ;; >: >- >>- >--|-> >>-|-> >= >== >>== >=|=:=>>
			    ;; >> >>> >>>>
			    (">" (rx (+ (or ">" "<" "|" "/" ":" "=" "-"))))
			    ;; #: #= #! #( #? #[ #{ #_ #_( ## ### #####
			    ("#" (rx (or ":" "=" "!" "(" "\?" "\[" "{" "_(" "_"
					 (+ "#"))))
			    ;; ~~ ~~~ ~=  ~-  ~@ ~> ~~>
			    ("~" (rx (or ">" "=" "-" "@" "~>" (+ "~"))))
			    ;; __ ___ ____ _|_ __|____|_
			    ("_" (rx (+ (or "_" "|"))))
			    ;; Fira code: 0xFF 0x12
			    ("0" (rx (and "x" (+ (in "A-F" "a-f" "0-9")))))
			    ;; Fira code:
			    "Fl"  "Tl"  "fi"  "fj"  "fl"  "ft"
			    ;; The few not covered by the regexps.
			    "{|"  "[|"  "]#"  "(*"  "}#"  "$>"  "^="))
  ;; Enables ligature checks globally in all buffers. You can also do it
  ;; per mode with `ligature-mode'.
  (global-ligature-mode t))

;; Auto-indent
;; (use-package aggressive-indent
;;   :hook
;;   (emacs-lisp-mode . aggressive-indent-mode)
;;   (python-mode . aggressive-indent-mode)
;;   :config
;;   (global-aggressive-indent-mode 1))

;; For use when lsp does not contain formatter methods
;; (use-package format-all
;;   :hook
;;   (prog-mode . format-all-mode)
;;   (python-mode . (lambda ()
;; 		   (setq-local format-all-formatters '(("Python" (ruff))))))
;;   (nix-mode . (lambda ()
;; 		(setq-local format-all-formatters '(("Nix" (alejandra "--quiet")))))))

(use-package yaml-mode)


(use-package reformatter
  :hook (python-mode . ruff-format-on-save-mode)
  :config
  (reformatter-define ruff-format :program "ruff"
    :args (list "format" "--stdin-filename" input-file "-")))

;; Custom Functions

(defun copy-envrc-and-setup-direnv ()
  "Copy .envrc from ~/projects/flake-templates/.envrc to a specified directory, create a .direnv directory there, and run `direnv-allow`."
  (interactive)
  (let ((source-file "~/projects/flake-templates/.envrc")
        (target-dir (read-directory-name "Specify target directory (default: current directory): " default-directory)))
    ;; Copy the .envrc file to the target directory
    (copy-file source-file (expand-file-name ".envrc" target-dir) t)
    ;; Create the .direnv directory in the target directory
    (make-directory (expand-file-name ".direnv" target-dir) t)
    ;; Change to the target directory
    (let ((default-directory target-dir))
      ;; Run direnv-allow
      (envrc-allow))
    ;; Notify the user
    (message "Copied .envrc to %s, created .direnv, and ran direnv-allow." target-dir)))

(defun smerge-keep-all-upper ()
  "Keep upper version for all conflicts in buffer."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (while (ignore-errors (not (smerge-next)))
      (smerge-keep-upper))))


(use-package ob-mermaid
  :config
  (org-babel-do-load-languages
   'org-babel-load-languages
   '((mermaid . t)
     (scheme . t)
     (python . t)
     (haskell . t))))


;;; emacs.el ends here
