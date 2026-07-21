# PATCH — Split zoxide query input on spaces for multi-keyword matching

## Problem

`zoxide-consult-builder` passes the user's input as a **single** keyword argument:

```elisp
(list "zoxide" "query" "-ls" "con 3")
→ zoxide query -ls "con 3"
```

Zoxide treats `"con 3"` as one literal search term — does NOT find "config_3" because the substring isn't contiguous.

Consult-buffer (`orderless`) splits by spaces internally, so `"con 3"` matches "config" AND "3" across the string.

## Fix

Split the input on whitespace so zoxide receives **multiple** keywords:

```elisp
(defun zoxide-consult-builder (input)
  "Build command line for `zoxide query -ls' from INPUT."
  (if (or (not input) (string-empty-p input))
      '("zoxide" "query" "-ls")
    (apply #'list "zoxide" "query" "-ls"
           (split-string input)))))
```

Before:
```
input: "con 3" → zoxide query -ls "con 3" → 0 results
```

After:
```
input: "con 3" → zoxide query -ls con 3 → finds config_3
```

## Affected locations

- `zoxide-consult-builder` in `emacs-zoxide/zoxide.el`
