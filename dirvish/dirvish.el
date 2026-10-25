;; -*- lexical-binding: t; -*-
;;
;; =============================================================================
;;  dirvish/dirvish.el — Dirvish (a polished Dired) for Firemacs
;;
;;  Dirvish enhances the built-in Dired into a full file manager: a full-frame
;;  layout with parent-directory panes, a live preview pane, file icons,
;;  version-control state and git log lines, all driven by Dired commands.
;;
;;  `dirvish-override-dired-mode' makes Dirvish take over Dired globally, so
;;  every existing Dired entry point in this config keeps working and gains
;;  the Dirvish treatment:
;;      - `C-e'  (`my/dired-from-terminal', keybinds.el)
;;      - `M-x dired'
;;      - any `dired' call (e.g. from `my/zoxide-travel-to-dired')
;;
;;  Entry points
;;  ------------
;;      C-c f           `dirvish' — full-frame file manager (layout + preview)
;;      M-x dirvish     same
;;      M-x dirvish-dwim    open in the current window instead of full-frame
;;      ?               `dirvish-dispatch' — transient cheatsheet (in a session)
;;
;;  Inside a Dirvish buffer the keymap inherits `dired-mode-map', so all the
;;  Dired bindings from dired.el and evil-collection still apply; Dirvish only
;;  adds `q' (`dirvish-quit') to close the whole session.
;;
;;  Dependencies
;;  ------------
;;  - GNU ls (coreutils) supporting long options — present on this system
;;  - fd — for the asynchronous large-directory listing path
;;  - nerd-icons — icon backend (already pulled in by doom-modeline.el)
;; =============================================================================

(use-package dirvish
  :ensure t
  :demand t
  :init
  ;; Let Dirvish take over Dired globally.  Done in `:init' so the advice on
  ;; `dired-noselect' & co. is installed before any Dired buffer is created.
  (dirvish-override-dired-mode)

  :bind
  ("C-c f" . dirvish)             ;; full-frame file manager

  :config
  ;; Dirvish wants `ls' switches spelled out with long option names so its
  ;; `ls' menu can parse and recompose them.  This intentionally supersedes
  ;; the short `-alhgG' switches set in dired.el — this module loads after
  ;; dired.el, so the value here wins.
  (setq dired-listing-switches
        "-l --almost-all --human-readable --group-directories-first --no-group")

  ;; Details rendered next to each file.  `vc-state', `subtree-state' and
  ;; `nerd-icons' always sit in fixed positions; the trailing attributes
  ;; (`git-msg', `file-time', `file-size') render in the order listed here.
  (setq dirvish-attributes
        '(nerd-icons subtree-state vc-state collapse git-msg file-time file-size))

  ;; One header line spanning every pane, and no leading bar image, to give
  ;; the file listing more horizontal room in a terminal.
  (setq dirvish-use-header-line 'global)
  (setq dirvish-mode-line-bar-image-width 0)

  ;; Compact mode line: sort order and symlink marker on the left; omit/yank
  ;; state and the index position on the right.
  (setq dirvish-mode-line-format
        '(:left (sort symlink) :right (omit yank index)))

  ;; List very large directories asynchronously with `fd' instead of blocking
  ;; Emacs on a synchronous `ls' of tens of thousands of entries.
  (setq dirvish-large-directory-threshold 20000)

  ;; Quick-access bookmarks for `M-x dirvish-quick-access'.
  ;; The option (and its `:set' that builds the transient menu) lives in the
  ;; `dirvish-quick-access' extension, so it can only be customized once that
  ;; file is loaded — hence the deferred `customize-set-variable' below.
  (with-eval-after-load 'dirvish-quick-access
    (customize-set-variable
     'dirvish-quick-access-entries
     '(("h" "~/"                          "Home")
       ("c" "~/.config/"                  "Config")
       ("d" "~/Downloads/"                "Downloads")
       ("n" "/nix/store"                  "Nix store")
       ("t" "~/.local/share/Trash/files/" "Trash"))))

  ;; `dirvish-dispatch' (the transient cheatsheet) and friends are autoloaded
  ;; from dirvish-extras.el.  Bind `?' for Evil users: Evil's normal state
  ;; map would otherwise shadow the mode map and turn `?' into a search.
  (general-def 'normal dirvish-mode-map
    "?" 'dirvish-dispatch))

(provide 'dirvish-config)
;; dirvish.el ends here
