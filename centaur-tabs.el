;; -*- lexical-binding: t; -*-
;;
;; =============================================================================
;;  centaur-tabs.el — Centaur Tabs Configuration
;;
;;  Aesthetic, modern-looking tab bar at the top of each frame/window.
;;  Integrates with the firebat theme and Nerd Font icons.
;;  Designed for terminal (-nw) use with Evil keybindings.
;; =============================================================================

(use-package centaur-tabs
  :demand t
  :config
  ;; ── Core enable ──────────────────────────────────────────────
  (centaur-tabs-mode t)
  (centaur-tabs-headline-match)

  ;; ── Group label in tab line ──────────────────────────────────
  ;; Override the default display-line format (tab-line-format or
  ;; header-line-format, whichever centaur-tabs chose) to prepend
  ;; the current group name.  The group-name segment is an :eval
  ;; form so it's always current — centaur-tabs' own tab bar
  ;; caching is unaffected.
  (let ((fmt-var (symbol-value 'centaur-tabs-display-line-format)))
    (set-default fmt-var
                 `((:eval (my/centaur-tabs-group-name))
                   (:eval (centaur-tabs-line)))))

  ;; ── Tab label — active/inactive indicator ──────────────────
  ;; Each tab is prepended with  (active) or  (inactive) so
  ;; you can tell at a glance which window's tab bar is focused.
  (setq centaur-tabs-tab-label-function 'my/centaur-tabs-tab-label)

  ;; ── Tab style (terminal-friendly) ────────────────────────────
  ;; "bar" is cleanest in terminal; "rounded", "chamfer", "slant"
  ;; also work.  Avoid "wave" and "zigzag" in -nw mode.
  (setq centaur-tabs-style "bar")

  ;; ── File icons (handled inside the custom label function) ───
  ;; Built-in icon rendering is disabled — the active/inactive
  ;; indicator (/) is prepended before the Nerd Font file icon
  ;; inside `my/centaur-tabs-tab-label' so the order is:
  ;;     statuscolumn.el   (not    statuscolumn.el)
  (setq centaur-tabs-set-icons nil)
  (setq centaur-tabs-plain-icons nil)
  (setq centaur-tabs-gray-out-icons 'buffer)

  ;; ── Selected-tab indicator bar ───────────────────────────────
  (setq centaur-tabs-set-bar 'under)        ;; Underline active tab

  ;; ── Close button & modified marker ───────────────────────────
  (setq centaur-tabs-set-close-button nil)  ;; Hide close button (cleaner)
  (setq centaur-tabs-set-modified-marker t) ;; Show "*" on modified buffers

  ;; ── Tab height (terminal-friendly) ───────────────────────────
  (setq centaur-tabs-height 24)
  (setq centaur-tabs-bar-height (+ 8 centaur-tabs-height))

  ;; ── Buffer grouping ──────────────────────────────────────────
  ;; Group buffers by project/mode so related buffers sit together.
  (setq centaur-tabs-cycle-scope 'tabs)     ;; Cycle within visible tabs

  ;; ── Hide tabs in special buffers ─────────────────────────────
  ;; In these modes, the tab bar would add clutter with no benefit.
  ;; vterm deliberately excluded — tab bar shows there too.
  (add-hook 'help-mode-hook       'centaur-tabs-local-mode)
  (add-hook 'apropos-mode-hook    'centaur-tabs-local-mode)

  ;; ── Tab navigation keybindings ───────────────────────────────
  ;; Non-Evil bindings for tab cycling (works from any state).
  (define-key centaur-tabs-mode-map (kbd "<M-tab>") 'centaur-tabs-forward)
  (define-key centaur-tabs-mode-map (kbd "C-<tab>") 'centaur-tabs-forward)
  (define-key centaur-tabs-mode-map (kbd "C-S-<iso-lefttab>") 'centaur-tabs-backward)

  ;; ── Additional convenience commands ──────────────────────────
  ;; Jump to a tab by typing a displayed character (ace-jump style)
  ;; Bound to SPC . in the leader key, but available here too:
  ;; (centaur-tabs-ace-jump)
  )

;; ── Group label segment ─────────────────────────────────────────
;; Prepend the current tab group name (with icon) at the leftmost
;; edge of the centaur-tabs bar, so you always know which group the
;; current buffer belongs to at a glance.
;;
;; This is called from the display-line-format as an :eval form,
;; so it runs on every redisplay — project branch lookups are
;; cached and only refreshed on buffer switches.

;; ── Group label face ───────────────────────────────────────────
;; defface ensures the face exists with proper defaults before the
;; firebat theme overrides it via custom-theme-set-faces in theme.el.

(defface my/centaur-tabs-group-face
  '((t (:foreground "#ff4400" :background "#2b2b2b" :weight bold)))
  "Face for the centaur-tabs group name segment."
  :group 'centaur-tabs)

;; ── Git branch cache ───────────────────────────────────────────
;; Invalidate the cache whenever the current buffer changes so that
;; git is only invoked once per buffer switch, not on every redraw.

(defvar my/centaur-tabs--branch-cache (make-hash-table :test 'equal)
  "Hash table mapping project path → git branch name.
Cleared on buffer switch.")

(defvar my/centaur-tabs--last-buffer nil
  "Last buffer for which `my/centaur-tabs--branch-cache' was valid.")

(defun my/centaur-tabs--invalidate-branch-cache ()
  "Clear the branch cache when the current buffer changes."
  (unless (eq (current-buffer) my/centaur-tabs--last-buffer)
    (clrhash my/centaur-tabs--branch-cache)
    (setq my/centaur-tabs--last-buffer (current-buffer))))

(defun my/centaur-tabs--git-info (project-path)
  "Return \"branch:hash\" for PROJECT-PATH, or \"󱃓\" on failure.
Result is cached per project path."
  (let ((cached (gethash project-path my/centaur-tabs--branch-cache 'missing)))
    (if (not (eq cached 'missing))
        cached
      (let ((result
             (condition-case nil
                 (let* ((branch-str
                         (with-output-to-string
                           (with-current-buffer standard-output
                             (call-process "git" nil '(t nil) nil
                                           "-C" project-path
                                           "rev-parse" "--abbrev-ref" "HEAD"))))
                        (hash-str
                         (with-output-to-string
                           (with-current-buffer standard-output
                             (call-process "git" nil '(t nil) nil
                                           "-C" project-path
                                           "rev-parse" "--short" "HEAD")))))
                   (setq branch-str (string-trim branch-str)
                         hash-str   (string-trim hash-str))
                   (if (or (string-empty-p branch-str)
                           (string= branch-str "HEAD")
                           (string-empty-p hash-str))
                       "󱃓"
                     (format "%s:%s" branch-str hash-str)))
               (error "󱃓"))))
        (puthash project-path result my/centaur-tabs--branch-cache)
        result))))

;; ── Tab label — active/inactive indicator ─────────────────────
;; This replaces the default `centaur-tabs-buffer-tab-label' so
;; every tab name is preceded by  or .

(defun my/centaur-tabs-tab-label (tab)
  "Return a label for TAB with active/inactive indicator.

   init.el   (active tab, indicator #ff4400)
   theme.el   (inactive tab, indicator #444444)"
  (let* ((tabset (centaur-tabs-current-tabset))
         (selected-p (and tabset (centaur-tabs-selected-p tab tabset)))
         (indicator (if selected-p "" ""))
         (indicator-face (if selected-p
                             'my/centaur-tabs-indicator-active
                           'my/centaur-tabs-indicator-inactive))
         (buf (car tab))
         (bufname (buffer-name buf)))
    ;; Use font-lock-face (not face) so the outer propertize in
    ;; centaur-tabs-line-tab (which sets 'face on the whole tab)
    ;; doesn't override our indicator colors.
    (format " %s %s"
            (propertize indicator 'font-lock-face indicator-face)
            bufname)))

;; ── Label construction ─────────────────────────────────────────

(defun my/centaur-tabs-group-name ()
  "Return a propertized string showing the current centaur-tabs group.

For **Project** groups the label shows   <branch>  (or  󱃓  when the
git branch cannot be determined).  All other groups show their
standard icon and group name (e.g.   Elisp ,   Common ).
The tooltip always shows the full group name."
  (my/centaur-tabs--invalidate-branch-cache)
  (let* ((group (or (centaur-tabs-buffer-groups-result)
                    centaur-tabs-common-group-name))
         (tooltip (format "Current group: %s" group))
         (label
          (if (string-match "^Project: \\(.+\\)" group)
              ;; Project group — show   <branch>  (or  󱃓  on failure)
              (let* ((proj-path (match-string 1 group))
                     (info      (my/centaur-tabs--git-info proj-path)))
                (if (string= info "󱃓")
                    (format " %s " info)
                  (format "  %s " info)))
            ;; Non-project group — show standard icon + group name
            (let ((icon (cond ((string-match-p "Elisp" group)   "")
                              ((string-match-p "Magit" group)   "")
                              ((string-match-p "^Shell$" group) "")
                              ((string-match-p "^EShell$" group) "")
                              ((string-match-p "Dired" group)   "")
                              ((string-match-p "Org" group)     "")
                              ((string-match-p "^Emacs$" group) "")
                              (t ""))))
              (format " %s %s " icon group)))))
    (if (and group (not (string-empty-p group)))
        (propertize label
                    'face 'my/centaur-tabs-group-face
                    'pointer centaur-tabs-mouse-pointer
                    'help-echo tooltip)
      (propertize " ∅ " 'face 'my/centaur-tabs-group-face))))

(provide 'centaur-tabs)
;; centaur-tabs.el ends here
