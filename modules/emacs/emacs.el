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
