;; disable gui elements
(menu-bar-mode -1)
(scroll-bar-mode -1)
(tool-bar-mode -1)

;; FIX
;; enable line numbers
(setq display-line-numbers-mode t)

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

;; syntax highlighting
(use-package tree-sitter
  :config
  (global-tree-sitter-mode))

;; lsp support
(use-package lsp-mode)

(use-package lsp-ui
  :after (lsp-mode))

(use-package helm-lsp :commands helm-lsp-workspace-symbol)

(use-package lsp-metals
  :ensure t
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

;; python lsp
(use-package lsp-pyright
  :ensure t
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

;; formatting
(use-package format-all
  :hook
  (prog-mode . format-all-mode)
  (format-all-mode-hook . format-all-ensure-formatter)
  :config
  (setq format-all-show-errors 'warnings))

(use-package direnv
  :config
  (direnv-mode))

(use-package projectile
  :config
  (projectile-mode +1)
  (define-key projectile-mode-map (kbd "C-c p") 'projectile-command-map))
