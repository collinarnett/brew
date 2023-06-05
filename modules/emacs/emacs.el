;; disable gui elements
(menu-bar-mode -1)
(scroll-bar-mode -1)
(tool-bar-mode -1)

;; FIX
;; enable line numbers
(display-line-numbers-mode +1)

;; mode line
(use-package moody
  :config
  (setq x-underline-at-descent-line t)
  (moody-replace-mode-line-buffer-identification)
  (moody-replace-vc-mode)
  (moody-replace-eldoc-minibuffer-message-function))

;; font
(add-to-list 'default-frame-alist
             '(font . "Fira Code 16"))

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

;; git tool
(use-package magit)

;; lsp support
(use-package lsp-mode
  :hook
  (python-mode . lsp)
  (haskell-mode . lsp)
  (scala-mode . lsp)
  (nix-mode . lsp)
  (lsp-mode . lsp-lens-mode))

(use-package lsp-ui
  :after (lsp-mode))

(use-package which-key
    :config
    (which-key-mode))

(use-package helm-lsp :commands helm-lsp-workspace-symbol)

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
  :hook (scala-mode . lsp))

(use-package scala-mode
  :ensure nil
  :interpreter ("scala" . scala-mode))


;; python lsp
(use-package lsp-pyright
  :hook (python-mode . (lambda ()
                         (require 'lsp-pyright)
                         (lsp))))

;; haskell lsp
(use-package lsp-haskell
  :after (lsp-mode)
  :hook
  (haskell-mode-hook . #'lsp)
  (haskell-literate-mode-hook . #'lsp))

;; nix lsp
(use-package lsp-nix
  :after (lsp-mode)
  :ensure nil
  :demand t
  :custom
  (lsp-nix-nil-formatter ["alejandra"]))

(use-package nix-mode
  :hook (nix-mode . lsp-deferred))

;; minibuffer completion
(use-package helm
  :config
  (helm-mode 1))

;; text completion
(use-package company
  :config
  (add-hook 'after-init-hook 'global-company-mode))

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

(use-package direnv
  :config
  (direnv-mode))

;; project manager
(use-package projectile
  :config
  (projectile-mode +1)
  (setq projectile-project-search-path '("~/projects/"))
  (define-key projectile-mode-map (kbd "C-c p") 'projectile-command-map))

;; smart parenthesis
(use-package smartparens
  :config
  (require 'smartparens-config)
  (smartparens-global-mode t))

;; common lisp ide
(use-package slime
  :config
  (setq inferior-lisp-program "sbcl"
	slime-completion-at-point-functions 'slime-fuzzy-complete-symbol))

(use-package lisp-mode
  :config
  (add-to-list 'auto-mode-alist '("\\.cl\\'" . lisp-mode)))

;; jupyter
(use-package jupyter)

;; Enable nice rendering of diagnostics like compile errors.
(use-package flycheck
  :init (global-flycheck-mode))

(use-package flycheck-popup-tip
  :config
  (flycheck-popup-tip-mode))

;;; emacs.el ends here
