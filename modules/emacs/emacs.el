;; disable gui elements
(menu-bar-mode -1) 
(scroll-bar-mode -1) 
(tool-bar-mode -1)

(use-package moody
  :config
  (setq x-underline-at-descent-line t)
  (moody-replace-mode-line-buffer-identification)
  (moody-replace-vc-mode)
  (moody-replace-eldoc-minibuffer-message-function))

;; font 
(add-to-list 'default-frame-alist
             '(font . "Fira Code"))

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

(use-package dracula-theme
  :config
  (load-theme 'dracula t))

(use-package magit)
