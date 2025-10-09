# Installation and Setup Instructions

## Problem: Capture stuck in "processing"

If your captures are stuck with STATUS "processing", it's likely because **gptel is not installed**.

## Solution: Install gptel first

### Option 1: Install via package.el (recommended)

In Emacs, run:
```
M-x package-refresh-contents RET
M-x package-install RET gptel RET
```

### Option 2: Install via straight.el

```elisp
(straight-use-package 'gptel)
```

### Option 3: Install via use-package

Add to your init.el:
```elisp
(use-package gptel
  :ensure t)
```

## Then load setup.el

After gptel is installed:

1. **Add your API key to authinfo:**
   ```
   echo "machine api.anthropic.com login apikey password sk-ant-YOUR-API-KEY" >> ~/.authinfo
   ```

2. **Load the setup:**
   ```
   M-x load-file RET ~/Sync/claude/bm/setup.el RET
   ```

3. **Test it:**
   ```
   M-x org-capture RET u RET
   ```
   Enter a URL and watch it process.

## Debugging

If issues persist:

1. **Check Messages buffer**: `C-h e` or `M-x view-echo-area-messages`

2. **Test gptel**: Run in Emacs:
   ```elisp
   (require 'gptel)
   (message "gptel loaded: %s" (featurep 'gptel))
   ```

3. **Enable logging**:
   ```elisp
   (setq org-capture-ai-enable-logging t)
   ```

4. **Manually reprocess stuck entry**: Visit the entry in bookmarks.org and run:
   ```
   M-x org-capture-ai-reprocess-entry
   ```

## Complete Installation Checklist

- [ ] Install gptel package
- [ ] Add Anthropic API key to ~/.authinfo
- [ ] Load setup.el
- [ ] Test with a capture
- [ ] Check that entry completes (STATUS: completed)
