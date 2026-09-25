;; -*- lexical-binding: t; -*-
;;
;; =============================================================================
;;  evil-config.el — Evil-mode add-ons
;;
;;  Extra Evil configuration that is kept out of the core `evil' setup in
;;  init.el.  Loaded from init.el section 3d (right after evil-collection).
;;
;;  Contents:
;;    evil-surround — add/change/delete surrounding pairs (`ys', `cs', `ds').
;;      - `global-evil-surround-mode' enables the operators everywhere.
;;      - `Y' in visual state runs `my/evil-surround-region-inline', an
;;        `evil-surround-region' that never puts the delimiters on their own
;;        lines.  Stock `evil-surround-region' (and the visual `S' binding)
;;        keeps surround.vim's linewise behaviour: on a linewise region (`V')
;;        or a multi-line motion it wraps like
;;
;;            '
;;            ;; Welcome to Emacs + Evil
;;            '
;;
;;        while the inline command always produces
;;
;;            ';; Welcome to Emacs + Evil'
;;
;;  Why `:demand t': use-package treats `:bind' as a *deferred loading*
;;  keyword, so without it evil-surround is not actually loaded at startup and
;;  the `:config' body would not run until the first `Y' press.  `:demand t'
;;  loads it (and enables the global mode) eagerly at startup, which is what
;;  makes `ys'/`cs'/`ds' available immediately.
;; =============================================================================

(defun my/evil-surround-region-inline (beg end type char)
  "Surround BEG..END with CHAR, never breaking the delimiters onto new lines.

This is `evil-surround-region' minus its linewise special case.  A
linewise region (visual-line `V', a multi-line motion) is trimmed to its
first and last character before surrounding, so linewise-selecting a line
and typing `Y' produces

    `text'

instead of

    `
    text
    `

Leading indentation is left outside the delimiters, and trailing
whitespace is ignored:

    (do-thing)  ->  `(do-thing)'

Characterwise regions (`v', `viw', ...) already surround inline and are
passed straight through to `evil-surround-region'."
  (interactive (evil-surround-input-region-char))
  (if (memq type '(line screen-line))
      (let ((b (save-excursion (goto-char beg) (back-to-indentation) (point)))
            (e (save-excursion (goto-char (max beg (1- end)))
                               (line-end-position))))
        (evil-surround-region b e 'inclusive char))
    (evil-surround-region beg end type char)))

(use-package evil-surround
  :ensure t
  :demand t
  :bind (:map evil-visual-state-map
              ("Y" . my/evil-surround-region-inline))
  :config
  (global-evil-surround-mode 1))

(provide 'evil-config)
;; evil-config.el ends here
