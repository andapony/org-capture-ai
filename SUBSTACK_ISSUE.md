# Substack URL Capture Issue

## Problem Description

### Overview
Bookmark capture fails for Substack URLs, leaving entries stuck in "processing" status with no error messages. The root cause is that Substack serves JavaScript-rendered content that cannot be processed by Emacs's `url-retrieve` function.

### Technical Details

**What happens:**
1. User captures a Substack URL (e.g., `https://photonlines.substack.com/p/visual-data-structures-cheat-sheet`)
2. `url-retrieve` fetches the HTML (243KB received)
3. Content extraction returns 0 characters
4. LLM API rejects empty content with HTTP 400: "messages: at least one message is required"
5. Entry remains stuck in "processing" status indefinitely

**Root cause:**
Substack serves different HTML to different clients:
- **Browsers/curl:** Full server-rendered HTML with `<body>`, `<article>` tags and article content (~488KB)
- **Emacs url-retrieve:** JavaScript SPA shell containing only JSON data in `<script>` tags (~243KB)

The HTML served to `url-retrieve` contains:
```html
<script>window._preloads = JSON.parse("{...massive JSON object...}");</script>
```

But NO `<body>`, `<article>`, or `<main>` tags. The actual article content is loaded client-side via JavaScript execution, which `url-retrieve` cannot perform.

### Impact
- **Substack URLs:** Complete failure to extract content
- **Other JavaScript-heavy sites:** May experience similar issues
- **Traditional server-rendered sites:** Work correctly

## Fixes Applied

### 1. Empty Content Validation (Implemented)
**Location:** `org-capture-ai.el:661-679`

**What it does:**
- Checks if extracted content is empty or too short (< 50 characters)
- Fails gracefully with clear error message instead of sending empty content to LLM
- Sets entry STATUS to "error" with descriptive ERROR property
- Logs diagnostic information to `*org-capture-ai-log*`

**Error message shown:**
```
Content extraction failed - no readable text found (0 chars)
```

**Benefits:**
- No more silent failures
- No more API errors (HTTP 400)
- Clear feedback about what went wrong
- Proper cleanup of markers and status

### 2. User-Agent Header (Implemented)
**Location:** `org-capture-ai.el:224-226`

**What it does:**
- Sets Chrome user agent when fetching URLs
- Helps with sites that serve different content based on client

**Code:**
```elisp
(let ((url-request-extra-headers
       '(("User-Agent" . "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"))))
  (url-retrieve url ...))
```

**Limitations:**
- Doesn't solve Substack issue (they likely check for JavaScript capability)
- May help with other sites that do simple user-agent detection

## Proposed Solutions

### Option 1: Accept Limitation (Recommended for Now)

**Description:**
Leave current implementation as-is with validation fix.

**Pros:**
- ✅ Already implemented
- ✅ No additional dependencies
- ✅ Clear error messages
- ✅ Works for most websites
- ✅ Simple and maintainable

**Cons:**
- ❌ Substack URLs won't work
- ❌ User must manually handle these cases

**User workflow for Substack:**
1. Capture URL (will fail with clear error)
2. Manually visit URL in browser
3. Copy/paste article text into entry body
4. Or use browser extension to capture

**Recommendation:** Use this approach initially. Monitor which sites fail and consider other options if many important sites are affected.

---

### Option 2: External Fetching Tool

**Description:**
Use `curl` or `wget` via shell command instead of `url-retrieve` for HTML fetching.

**Implementation:**
```elisp
(defun org-capture-ai-fetch-url-curl (url success-callback error-callback)
  "Fetch URL using curl to get full server-rendered HTML."
  (let* ((temp-file (make-temp-file "org-capture-ai-"))
         (process (start-process "org-capture-ai-curl" nil
                                "curl" "-L" "-s" "-o" temp-file
                                "-A" "Mozilla/5.0..." url)))
    (set-process-sentinel
     process
     (lambda (proc event)
       (when (string= event "finished\n")
         (with-temp-buffer
           (insert-file-contents temp-file)
           (funcall success-callback (buffer-string)))
         (delete-file temp-file))))))
```

**Pros:**
- ✅ Gets full HTML from Substack (tested: works)
- ✅ Better compatibility with various sites
- ✅ Handles redirects automatically (`-L` flag)
- ✅ No additional packages needed (curl is standard on most systems)

**Cons:**
- ❌ Dependency on external `curl` command
- ❌ May not be available on all systems (Windows)
- ❌ More complex error handling
- ❌ Still won't work for sites that require JavaScript execution

**Recommendation:** Good middle-ground solution. Implement as configurable option: `org-capture-ai-fetch-method` with choices `'url-retrieve` or `'curl`.

---

### Option 3: Parse Substack JSON Data

**Description:**
Extract article content from the JSON object in `window._preloads` that Substack includes in the HTML.

**Implementation approach:**
```elisp
(defun org-capture-ai-extract-substack-json (html)
  "Extract article content from Substack's _preloads JSON."
  (when (string-match "window._preloads\\s-*=\\s-*JSON.parse(\"\\(.*?\\)\")" html)
    (let* ((json-str (match-string 1 html))
           ;; Unescape JSON string
           (json-str (replace-regexp-in-string "\\\\\"" "\"" json-str))
           (data (json-parse-string json-str)))
      ;; Extract post content from nested JSON structure
      (alist-get 'body (alist-get 'post data)))))
```

**Pros:**
- ✅ Specific solution for Substack
- ✅ No external dependencies
- ✅ Gets actual article content

**Cons:**
- ❌ Very brittle - breaks if Substack changes JSON structure
- ❌ Only solves Substack, not other JavaScript sites
- ❌ Complex JSON parsing and unescaping
- ❌ May not include all content (images, formatting)
- ❌ Maintenance burden

**Recommendation:** Not recommended unless Substack is a critical use case. Too specific and fragile.

---

### Option 4: Headless Browser

**Description:**
Use a headless browser (like Puppeteer, Playwright, or Emacs's `shr` with `eww`) to render JavaScript and extract content.

**Implementation options:**

**A. External headless browser:**
```bash
# Using Puppeteer/Playwright via Node.js
node fetch-url.js "https://substack.com/..." > output.html
```

**B. Emacs EWW renderer:**
```elisp
(defun org-capture-ai-fetch-url-eww (url success-callback error-callback)
  "Fetch URL using EWW to render JavaScript."
  (with-current-buffer (eww url)
    ;; Wait for rendering...
    (funcall success-callback (buffer-string))))
```

**Pros:**
- ✅ Handles JavaScript rendering
- ✅ Works with most modern websites
- ✅ Gets complete rendered content

**Cons:**
- ❌ Significant complexity
- ❌ External dependencies (Node.js, Puppeteer)
- ❌ Slow (browser startup + rendering time)
- ❌ Resource intensive (memory, CPU)
- ❌ EWW option is synchronous (blocks Emacs)
- ❌ Difficult error handling

**Recommendation:** Overkill for this use case. Only consider if many JavaScript-heavy sites are needed.

---

### Option 5: Fallback to Reader Mode Services

**Description:**
Use third-party reader mode APIs (like Mozilla's Readability service, Outline.com, or archive.is) as fallback when direct fetch fails.

**Implementation:**
```elisp
(defun org-capture-ai-fetch-url-with-fallback (url success-callback error-callback)
  "Fetch URL, falling back to reader service if extraction fails."
  (org-capture-ai-fetch-url url
    (lambda (html)
      (let ((content (org-capture-ai-extract-readable-content html)))
        (if (> (length content) 50)
            (funcall success-callback html)
          ;; Fallback to outline.com
          (org-capture-ai-fetch-url
           (concat "https://outline.com/" url)
           success-callback
           error-callback))))
    error-callback))
```

**Pros:**
- ✅ Works for JavaScript sites
- ✅ Clean, reader-friendly content
- ✅ No local dependencies
- ✅ Fast

**Cons:**
- ❌ Depends on third-party services
- ❌ Privacy concerns (URLs sent to external service)
- ❌ May break if service changes/shuts down
- ❌ Rate limiting possible
- ❌ Some services require API keys

**Recommendation:** Could work as opt-in fallback. Make it configurable and document privacy implications.

## Recommended Implementation Plan

### Phase 1: Immediate (Already Complete)
- ✅ Validation fix (prevents errors, gives clear feedback)
- ✅ User-Agent header (helps with some sites)

### Phase 2: Near-term Enhancement (Recommended)
Implement **Option 2: External Fetching Tool** as configurable option:

```elisp
(defcustom org-capture-ai-fetch-method 'url-retrieve
  "Method to use for fetching URLs.
- 'url-retrieve: Use Emacs built-in (fast, no dependencies, limited compatibility)
- 'curl: Use external curl command (better compatibility, requires curl installed)"
  :type '(choice (const :tag "Emacs url-retrieve" url-retrieve)
                 (const :tag "External curl" curl))
  :group 'org-capture-ai)
```

**Benefits:**
- Solves Substack issue
- Maintains backward compatibility
- Gives users choice
- Simple implementation

### Phase 3: Future Consideration
If many JavaScript-heavy sites are needed, consider **Option 5: Reader Mode Services** as opt-in fallback with privacy warning.

## Testing Results

### Test URLs
1. **Traditional site (working):**
   - Example: Most blog sites, documentation sites
   - Result: ✅ Content extracted successfully

2. **Substack (failing):**
   - URL: `https://photonlines.substack.com/p/visual-data-structures-cheat-sheet`
   - With url-retrieve: ❌ 0 characters extracted
   - With curl: ✅ 14,218 characters extracted
   - With current validation: ✅ Clear error message shown

3. **Substack with validation fix:**
   - Error message: "Content extraction failed - no readable text found (0 chars)"
   - Status: "error"
   - ERROR property: Descriptive message logged
   - Result: ✅ Graceful failure with good UX

## Configuration Examples

### For users who need Substack support:
Once Option 2 is implemented:
```elisp
(setq org-capture-ai-fetch-method 'curl)
```

### For users who want fallback service:
Once Option 5 is implemented:
```elisp
(setq org-capture-ai-fetch-method 'url-retrieve)
(setq org-capture-ai-enable-fallback-service t)
(setq org-capture-ai-fallback-service 'outline) ; or 'readability
```

## Investigation Update (2025-10-18)

### Redirect Handling Discovery

**Key findings:**
1. ✅ **Redirect issue identified**: `url-retrieve` does NOT automatically follow redirects - it returns `:redirect` in status plist
2. ✅ **Redirect handling implemented**: Added code to detect and recursively follow redirects
3. ✅ **Redirect works**: `https://substack.com/home/post/p-175453043` → `https://onlyvariance.substack.com/p/getting-jacked-is-simple`
4. ❌ **Still fails**: Even the final URL returns JavaScript shell (113KB) instead of full HTML (236KB)

### Why url-retrieve Still Fails

**Test results:**
- `curl` with User-Agent: Gets 236KB with `<body>` and `<article>` ✅
- `url-retrieve` with same User-Agent: Gets 113KB JavaScript shell ❌

**Conclusion:** Substack detects non-browser clients through:
- Missing Accept headers (text/html, application/xhtml+xml, etc.)
- Missing or unusual cookies
- Absence of JavaScript execution capability
- TLS fingerprinting or other browser detection methods

**Evidence:** Our User-Agent header alone is not sufficient. Substack serves the SPA to anything that doesn't look like a real browser, regardless of the User-Agent string.

## Resolution (2025-10-19)

**FIXED!** Implemented Option 2 (curl-based fetching) successfully.

### Final Implementation

Added `org-capture-ai-fetch-method` customization variable (defaults to `'curl`):
- `'curl`: Uses external curl command (better compatibility, requires curl)
- `'url-retrieve`: Uses Emacs built-in (faster but limited compatibility)

### Key Code Changes

1. **New customization** (`org-capture-ai.el:219-225`):
   ```elisp
   (defcustom org-capture-ai-fetch-method 'curl ...)
   ```

2. **Dispatcher function** (`org-capture-ai-fetch-url:227-236`):
   Routes to curl or builtin based on setting

3. **Curl implementation** (`org-capture-ai-fetch-url-curl:238-269`):
   - Uses async `start-process` with curl
   - Follows redirects (`-L`)
   - Sets proper User-Agent
   - Handles temp files and cleanup

4. **Validation** (`org-capture-ai--llm-analyze:679-693`):
   - Checks for empty/too-short content (< 50 chars)
   - Fails gracefully with clear error message
   - Sets STATUS to "error" with ERROR property

### Test Results

**Substack URL:** `https://substack.com/home/post/p-175453043`

With curl (WORKING):
- ✅ Fetched: 236,223 bytes
- ✅ Found `<article>` tag: YES
- ✅ Extracted: 19,188 chars of readable text
- ✅ Title: "Getting Jacked is Simple - by Dylan - Chaotic Neutral"
- ✅ LLM processing: Success

With url-retrieve (FAILED):
- ❌ Fetched: 113,594 bytes (JavaScript SPA shell)
- ❌ Found `<article>` tag: NO
- ❌ Extracted: 0 chars
- ❌ Reason: Substack serves JavaScript-only version to non-browsers

### Why url-retrieve Fails

Even with User-Agent headers and redirect handling, Substack detects non-browser clients through:
- Missing Accept headers
- Lack of JavaScript execution capability
- TLS fingerprinting
- Other browser detection methods

### Conclusion

**Status:** ✅ RESOLVED
**Method:** curl-based fetching (Option 2)
**Benefits:** Works with Substack and other JavaScript-heavy sites
**Fallback:** Users can switch to `'url-retrieve` if curl is unavailable
