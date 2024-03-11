;; -*- lexical-binding: t; -*-
;; disable gui elements
(menu-bar-mode -1)
(scroll-bar-mode -1)
(tool-bar-mode -1)
(global-display-line-numbers-mode)

(display-line-numbers-mode +1)

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


(use-package bind-key
  :ensure t
  :config
  (add-to-list 'same-window-buffer-names "*Personal Keybindings*"))

;; mode line
(use-package moody
  :config
  (setq x-underline-at-descent-line t)
  (moody-replace-mode-line-buffer-identification)
  (moody-replace-vc-mode)
  (moody-replace-eldoc-minibuffer-message-function))

;; font
(add-to-list 'default-frame-alist
             '(font . "Fira Code 12"))

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
  (evil-collection-init))

;; theme
(use-package dracula-theme
  :config
  (load-theme 'dracula t))

;; required for lsp-mode
(use-package yasnippet)

;; lsp support
(use-package lsp-mode)

(use-package lsp-ui
  :after (lsp-mode))

;; text completion
(use-package company
  :config
  (setq company-idle-delay 0.2
	company-tooltip-limit 20
	company-minimum-prefix-length 2)
  (add-hook 'after-init-hook 'global-company-mode))

(use-package helm-lsp :commands helm-lsp-workspace-symbol)

(use-package which-key
  :config
  (which-key-mode))

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
  :hook (python-mode . lsp-deferred))

(use-package jupyter)

;; haskell
(use-package lsp-haskell
  :hook
  (haskell-mode . lsp-deferred)
  (haskell-literate-mode. lsp-deferred))

;; (use-package haskell-mode
;;   :config
;;   (setq haskell-stylish-on-save t)
;;   :hook
;;   (haskell-mode . interactive-haskell-mode)
;;   :mode "\\.hs\\'")

(use-package reformatter)

(use-package ormolu
  :hook (haskell-mode . ormolu-format-on-save-mode)
  :bind
  (:map haskell-mode-map
	("C-c r" . ormolu-format-buffer)))

;; nix
(use-package lsp-nix
  :hook
  (nix-mode . lsp-deferred))

(use-package nix-mode
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

;; minibuffer completion
(use-package helm
  :init
  (helm-mode 1))

;; icons
(use-package nerd-icons)

;; dashboard
(use-package dashboard
  :after (nerd-icons)
  :config
  (dashboard-setup-startup-hook)
  (setq dashboard-startup-banner
	"/home/collin/brew/modules/emacs/hydra.txt")
  (setq dashboard-center-content t))

;; setup pinentry for gpg signing
(use-package pinentry)
(pinentry-start)

(use-package direnv ; direnv integration
  :after lsp
  :delight 'direnv-mode
  :config
  ;; Ensures that external dependencies are available before they are called.
  (add-hook 'prog-mode-hook #'direnv--maybe-update-environment)
  (setq direnv-always-show-summary nil)
  (direnv-mode 1))

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

(use-package lisp-mode
  :mode
  "\\.cl\\'")

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
(use-package aggressive-indent
  :hook
  (emacs-lisp-mode . aggressive-indent-mode)
  (python-mode . aggressive-indent-mode)
  :config
  (global-aggressive-indent-mode 1))

;; For use when lsp does not contain formatter methods
(use-package format-all
  :hook
  (prog-mode . format-all-mode)
  (python-mode . (lambda ()
		   (setq-local format-all-formatters '(("Python"
							(black)
							(isort))))))
  (nix-mode . (lambda ()
		(setq-local format-all-formatters '(("Nix" (alejandra "--quiet")))))))

(use-package yaml-mode)

;;; emacs.el ends here
