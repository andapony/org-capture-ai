# org-capture-ai Bug Fix Session State

**Date:** 2025-10-19
**Session Focus:** Fixing Substack URL refresh failures

## Problem Solved (2025-10-19)

Substack URLs were failing to refresh - getting stuck in "processing" status or returning 0 characters of content.

**Root Cause:** Substack serves different HTML based on client detection:
- **Browsers/curl:** Full server-rendered HTML (236KB) with `<article>` tags
- **Emacs url-retrieve:** JavaScript SPA shell (113KB) with NO `<body>` or `<article>` tags

Even with User-Agent headers and redirect handling, `url-retrieve` cannot bypass Substack's client detection.

## Solution Implemented

### 1. curl-based Fetching (Default)

**File:** `org-capture-ai.el:219-269`

Added configurable fetch method:
```elisp
(defcustom org-capture-ai-fetch-method 'curl ...)
```

**Implementation:**
- `org-capture-ai-fetch-url` - Dispatcher function
- `org-capture-ai-fetch-url-curl` - Uses external curl via async process
- `org-capture-ai-fetch-url-builtin` - Uses url-retrieve (fallback)

**Benefits:**
- ✅ Works with Substack and other JavaScript-heavy sites
- ✅ Follows redirects automatically
- ✅ Sets proper User-Agent
- ✅ Async via process sentinel

### 2. Content Validation

**File:** `org-capture-ai.el:679-693`

Prevents LLM errors when content extraction fails:
```elisp
(if (or (not text) (string-empty-p text) (< (length text) 50))
    ;; Fail gracefully with clear error
    (progn ...)
  ;; Process with LLM
  ...)
```

## Test Results

**Substack URL:** `https://substack.com/home/post/p-175453043`

| Method | Bytes | Has `<article>` | Extracted Text | Result |
|--------|-------|----------------|----------------|--------|
| curl | 236,223 | YES | 19,188 chars | ✅ SUCCESS |
| url-retrieve | 113,594 | NO | 0 chars | ❌ FAILED |

**Working output:**
```
[2025-10-19 08:14:01] Fetching URL: https://substack.com/home/post/p-175453043 (method: curl)
[2025-10-19 08:14:01] curl fetched: 236223 bytes
[2025-10-19 08:14:01] Found article: YES, main: NO, body: YES, using: article
[2025-10-19 08:14:01] Extracted 19188 chars of text, title: Getting Jacked is Simple - by Dylan - Chaotic Neutral
[2025-10-19 08:14:01] About to call llm-analyze with 19188 chars
```

## FUTURE WORK: Solve url-retrieve Problem

**Goal:** Make `url-retrieve` work with Substack (eliminate curl dependency)

### Investigation Notes

#### What We Know

1. **EWW works with url-retrieve**
   - User confirmed: `M-x eww https://substack.com/home/post/p-175453043` displays correctly
   - EWW uses `url-retrieve` by default (`eww-retrieve-command` is `nil`)
   - EWW has option to use external command via `eww-retrieve-command`

2. **Redirect behavior**
   - `url-retrieve` DOES automatically follow redirects
   - When redirect occurs, status plist contains `:redirect` key
   - Buffer contains final destination's content (not 302 response)
   - Confirmed: `https://substack.com/home/post/p-175453043` → `https://onlyvariance.substack.com/p/getting-jacked-is-simple`

3. **What url-retrieve returns for Substack**
   - 113,594 bytes (vs 236,223 with curl)
   - Contains NO `<body>` tag
   - Contains NO `<article>` tag
   - Contains NO `<main>` tag
   - Contains JavaScript with embedded JSON: `window._preloads = JSON.parse("...")`
   - This is a JavaScript SPA shell that renders content client-side

4. **Why User-Agent alone doesn't work**
   - We added: `Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120.0.0.0`
   - Substack still serves SPA shell
   - Likely detects via: Missing Accept headers, no JavaScript capability, TLS fingerprinting

#### Debug Code Locations

Currently removed but can be re-added for investigation:

**Fetch logging** (in `org-capture-ai-fetch-url-builtin`):
```elisp
;; After line 293 (before checking HTTP status):
(org-capture-ai--log "Buffer size: %d bytes, first 500 chars: %s"
                     (buffer-size)
                     (buffer-substring (point-min) (min (+ (point-min) 500) (point-max))))

;; After line 300 (when extracting content):
(org-capture-ai--log "Fetched HTML: %d bytes, has <body>: %s, has <article>: %s"
                     (length content)
                     (if (string-match "<body" content) "YES" "NO")
                     (if (string-match "<article" content) "YES" "NO"))

;; Save HTML for inspection:
(with-temp-file "/tmp/substack-fetched.html"
  (insert content))
(org-capture-ai--log "Saved HTML to /tmp/substack-fetched.html")
```

**DOM extraction logging** (in `org-capture-ai-extract-readable-content`):
```elisp
;; After line 430 (when selecting main node):
(org-capture-ai--log "Found article: %s, main: %s, body: %s, using: %s"
                     (if (dom-by-tag dom 'article) "YES" "NO")
                     (if (dom-by-tag dom 'main) "YES" "NO")
                     (if (dom-by-tag dom 'body) "YES" "NO")
                     (if main-node (dom-tag main-node) "NONE"))
```

#### Investigation Questions

1. **How does EWW render Substack content?**
   - EWW gets same 113KB SPA shell from `url-retrieve`
   - Does `shr` (Simple HTML Renderer) extract JSON data?
   - Does EWW have special handling for JavaScript pages?
   - Check: `zcat /usr/share/emacs/29.3/lisp/net/eww.el.gz | grep -A20 "defun eww-render"`

2. **Can we extract from embedded JSON?**
   - Pattern: `window._preloads = JSON.parse("...")`
   - Contains article content in nested structure
   - See SUBSTACK_ISSUE.md Option 3 for implementation approach
   - **Downside:** Brittle - breaks if Substack changes format

3. **What headers does curl send that url-retrieve doesn't?**
   ```bash
   # Compare headers
   curl -v -L "https://substack.com/home/post/p-175453043" 2>&1 | grep "^>"

   # Test with same headers in url-retrieve
   (let ((url-request-extra-headers
          '(("User-Agent" . "...")
            ("Accept" . "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
            ("Accept-Language" . "en-US,en;q=0.5")
            ("Accept-Encoding" . "gzip, deflate")
            ("Connection" . "keep-alive")
            ("Upgrade-Insecure-Requests" . "1"))))
     (url-retrieve url ...))
   ```

4. **Can we use shr directly?**
   - `(require 'shr)`
   - `(shr-insert-document dom)` - renders to current buffer
   - Check if shr has content extraction functions we can use

5. **Does url.el have any undocumented options?**
   - Check `url-retrieve` optional parameters
   - Check for global variables that affect behavior
   - `M-x describe-variable RET url- TAB` to see all options

#### Files to Reference

- **SUBSTACK_ISSUE.md** - Complete analysis with 5 solution options
- **org-capture-ai.el:271-310** - Current url-retrieve implementation
- **org-capture-ai.el:419-448** - Content extraction logic
- `/usr/share/emacs/29.3/lisp/net/eww.el.gz` - EWW source code
- `/usr/share/emacs/29.3/lisp/net/shr.el.gz` - Simple HTML Renderer

#### Next Steps for Investigation

1. **Test EWW's exact url-retrieve call**
   - Extract EWW's parameters and headers
   - Replicate in org-capture-ai
   - Compare HTML received

2. **Test with additional headers**
   - Add Accept, Accept-Language, etc.
   - Test if Substack serves different content

3. **Investigate shr rendering**
   - See if shr can extract text from the SPA shell
   - Check if there's server-rendered content we're missing

4. **Consider JSON extraction** (last resort)
   - Parse `window._preloads` JSON
   - Extract article content from nested structure
   - Add as fallback when no `<article>` found

## Current Configuration

Default fetch method is `curl`. To switch back to url-retrieve for testing:

```elisp
(setq org-capture-ai-fetch-method 'url-retrieve)
```

Then run refresh and check logs to see what url-retrieve returns.

## Files Modified

- `org-capture-ai.el` - Added curl fetching, content validation
- `SUBSTACK_ISSUE.md` - Complete analysis and resolution documentation
- `SESSION_STATE.md` - This file

## Summary

**Problem:** Substack URLs failed because url-retrieve gets JavaScript shell instead of full HTML

**Solution:** Implemented curl-based fetching (works perfectly)

**Future:** Investigate why EWW works with url-retrieve and replicate that approach to eliminate curl dependency
