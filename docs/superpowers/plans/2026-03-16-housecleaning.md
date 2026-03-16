# Housecleaning Plan

**Goal:** Targeted cleanup informed by architectural reflection — reduce boilerplate,
improve test realism, and separate opinionated configuration from core mechanics.
No behaviour changes. Each task is independently verifiable with `./run-tests.sh`.

---

## Task 1: Extract `org-capture-ai--with-entry` Macro

**Problem:** The triple `(save-excursion (org-with-point-at marker (org-back-to-heading t ...)))`
appears 31 times in the file. It's mechanical boilerplate that obscures the actual logic
in every function that mutates an entry.

**Fix:** Define a macro that captures the pattern:

```elisp
(defmacro org-capture-ai--with-entry (marker &rest body)
  "Execute BODY with point at the heading for the entry at MARKER.
Wraps BODY in `save-excursion', jumps to MARKER, and moves to the
heading with `org-back-to-heading'."
  (declare (indent 1))
  `(save-excursion
     (org-with-point-at ,marker
       (org-back-to-heading t)
       ,@body)))
```

Then replace every occurrence of the triple with `(org-capture-ai--with-entry marker ...)`.

**Files:** `org-capture-ai.el`

**Verification:** `./run-tests.sh` — behaviour is identical, only boilerplate changes.

- [ ] Define macro after the `;;; Internal Variables` section
- [ ] Replace all 31 occurrences throughout the file
- [ ] Validate with sexp tools
- [ ] Run full test suite
- [ ] Commit

---

## Task 2: Move LLM Mock Responses to Fixture Files

**Problem:** Mock LLM responses are hardcoded strings in `org-capture-ai-test-helpers.el`.
The fixture infrastructure already exists (`test-fixtures/llm-responses/`) with
`normal-summary.txt` and `normal-tags.txt`, but the helpers don't use them.
Inline strings are harder to update and don't capture realistic response formatting.

**Fix:** Add `normal-takeaways.txt` to the fixture directory and update
`org-capture-ai-test--mock-llm-responses` to load responses from fixture files
using `org-capture-ai-test--load-fixture`.

**Files:** `org-capture-ai-test-helpers.el`, `test-fixtures/llm-responses/normal-takeaways.txt`

**Verification:** `./run-tests.sh` — all tests pass with fixture-loaded responses.

- [ ] Add `test-fixtures/llm-responses/normal-takeaways.txt`
- [ ] Update `org-capture-ai-test--mock-llm-responses` to load from fixtures
- [ ] Run full test suite
- [ ] Commit

---

## Task 3: Separate Curated Tag Vocabulary into Its Own Section

**Problem:** The four tag defcustoms (`org-capture-ai-use-curated-tags`,
`org-capture-ai-tags-type`, `org-capture-ai-tags-status`, `org-capture-ai-tags-quality`,
`org-capture-ai-tags-domain`) are opinionated personal vocabulary — not core mechanics.
They're currently intermixed with configuration defcustoms, making it harder to find
the settings that actually affect behaviour.

**Fix:** Move them to a dedicated `;;; Curated Tag Vocabulary` section with a comment
explaining they are optional defaults, fully replaceable by the user.

**Files:** `org-capture-ai.el`

**Verification:** `./run-tests.sh` — no behaviour change, only section reorganisation.

- [ ] Add `;;; Curated Tag Vocabulary` section near the bottom of the defcustoms block
- [ ] Move the five tag defcustoms into it with an explanatory comment
- [ ] Validate with sexp tools
- [ ] Run full test suite
- [ ] Commit

---

## Deferred: Async Callback Chain

The three-level callback chain in `org-capture-ai--llm-analyze` is inherently hard
to read. The `apply-*` refactor helped, but the root issue is callback-passing style.
A proper fix would use `promise.el` or a continuation abstraction.

Deferred because: it's a significant rewrite, the current code is correct and tested,
and the `apply-*` extraction has already reduced the pain to a manageable level.
Revisit if the chain grows (e.g. a fourth LLM step is added).

## Deferred: Data Model

Storing structured data (takeaways, related entries) in pipe-separated property strings
is a limitation. A richer model would use org body structure or a sidecar file.

Deferred because: changing the storage format would break existing captured entries
and is a larger design decision than a housecleaning task.
