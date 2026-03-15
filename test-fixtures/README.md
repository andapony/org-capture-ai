# Test Fixtures

This directory contains test fixtures for org-capture-ai tests.

## Structure

```
test-fixtures/
├── html/              # HTML pages for testing URL fetch and parsing
├── llm-responses/     # Mock LLM responses for testing AI integration
└── snapshots/         # Expected output snapshots for regression tests
```

## HTML Fixtures

- `normal-article.html` - Standard article with good metadata
- `multiline-description.html` - Meta description with newlines (tests sanitization)
- `empty-body.html` - HTML with no readable content
- `only-scripts.html` - Page with only scripts/styles (no text content)
- `long-description.html` - Very long description (tests truncation)
- `special-chars.html` - Special characters, Unicode, emoji

## LLM Response Fixtures

The `llm-responses/` directory is reserved for mock LLM response fixtures. Currently,
tests use inline mock responses via `org-capture-ai-test--mock-gptel-request` rather
than file-based fixtures. Add `.txt` files here if you need test-specific LLM responses
and load them with:

```elisp
(org-capture-ai-test--load-fixture "llm-responses" "my-response.txt")
```

## Adding New Fixtures

When adding a new test case:

1. Create HTML fixture in `html/`
2. Create corresponding LLM responses in `llm-responses/` (if needed)
3. Update this README
4. Reference the fixture in your test using:
   ```elisp
   (org-capture-ai-test--load-fixture "html" "your-fixture.html")
   ```

## Snapshots

The `snapshots/` directory is reserved for expected-output snapshot files used in
snapshot-style regression tests. Currently no snapshot tests are implemented.
