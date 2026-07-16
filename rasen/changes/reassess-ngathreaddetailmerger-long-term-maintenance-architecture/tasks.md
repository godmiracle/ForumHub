## 1. Evidence Baseline and Contract Tests

- [x] 1.1 Inventory every existing NGA API/Web Fixture and inline content sample, classify each as real shape, cropped real shape, or artificial boundary, and record which source-policy requirement it proves.
- [x] 1.2 Add脱敏 paired Fixtures for API-valid, API-content-unusable/Web-valid, API-failure/Web-valid, Web-access-denied, and both-sources-unusable paths without credentials or identifiable正文.
- [x] 1.3 Add failing contract tests proving repeated paragraphs, repeated image URLs, middle-position content, whitespace/case-sensitive content, and unknown tags retain order and occurrences.
- [x] 1.4 Add request-count tests proving a valid or degraded API result performs no Web request and only an unusable API result enters Web fallback.
- [x] 1.5 Document the current evidence decision that a dual-source Semantic Reconciler is out of scope until the separate two-real-Fixture threshold is met.

## 2. Semantic Content Core

- [x] 2.1 Define source-neutral `ForumPostDocument`, source representations, schema/parser versions, structured diagnostics, parse quality, block nodes, inline nodes, generic resources, and provenance.
- [x] 2.2 Implement deterministic plain-text/body, image enumeration, accessibility, snapshot, and content-signature projectors over semantic nodes.
- [x] 2.3 Give every content occurrence stable display identity independent of payload equality, and make the duplicate paragraph/image tests from 1.3 pass.
- [x] 2.4 Implement explicit unsupported/malformed nodes and safe fallback behavior so unknown user-visible content is preserved with non-fatal diagnostics.
- [x] 2.5 Add privacy tests ensuring Release diagnostics cannot contain raw markup,正文, Cookie, Token, guest token, or user identifiers.

## 3. NGA Source Parsers and Metadata Mapping

- [x] 3.1 Implement an NGA BBCode tokenizer and parser-private syntax tree with recovery for text, line breaks, images, emoji, quotes, links, and unknown tags.
- [x] 3.2 Lower NGA BBCode syntax directly into semantic content blocks without passing through `structuredForumText` or `normalizedText`.
- [x] 3.3 Extend the exact `postcontent<floor>` Web extraction path with HTML/NGA markup lowering into the same semantic blocks, keeping DOM details inside the NGA parser layer.
- [x] 3.4 Map API root fields including `tsubject`, `tauthor`, `vrows`, `currentPage`, `totalPage`, and `attachPrefix`, while preserving per-post `pid`, `lou`, author, time, order, and attachment metadata.
- [x] 3.5 Return typed valid/degraded/unusable parse quality and structured diagnostics from both NGA source parsers, with unknown-but-readable content classified as degraded.
- [x] 3.6 Add parser contract tests for the real `47185513` shape: 0–11 floors, two ordered images, three emoji, quote variants, root title/author, and absolute/relative image representations.

## 4. Migrate Content Consumers

- [x] 4.1 Make `ForumThread.body` and `Reply.body` read-only plain-text projector outputs from semantic documents and remove any remaining authoritative stored normalized text.
- [x] 4.2 Migrate `ForumRichContentView` to render ordered semantic nodes directly, including generic emoji, quote, image, text, and unsupported fallback nodes.
- [x] 4.3 Migrate long-image rendering and image enumeration to the shared semantic document and verify they expose the same ordered media as native reading.
- [x] 4.4 Migrate sharing, reply/reference previews, and accessibility text to explicit projectors without reparsing raw markup or normalized text.
- [x] 4.5 Migrate pagination duplicate signatures to the dedicated content-signature projector and verify reply identity remains `source + stable post/floor identity`, not display text equality.
- [x] 4.6 Confirm V2EX, LINUX DO, mock data, previews, favorites, and history construct valid semantic documents without introducing source-specific branches in shared Views.

## 5. API-First NGA Acquisition Strategy

- [x] 5.1 Separate NGA transport observations, content parse results, quality validation, source selection, and final thread assembly into independently testable components.
- [x] 5.2 Return API-assembled detail immediately for valid/degraded content and make the no-Web request-count tests pass for the normal path.
- [x] 5.3 For an API-confirmed floor with unusable content, request Web and select the whole Web semantic document while retaining API identity/metadata and both source representations.
- [x] 5.4 Keep Web-only replies out of API-backed membership/order, emit a structured investigation diagnostic, and verify the same-floor fallback retains API `pid`, author, time, and floor.
- [x] 5.5 Define and implement the approved product behavior for complete API transport failure: Web-only readable fallback with explicitly unavailable metadata, or typed error plus original-page action.
- [x] 5.6 Return typed errors when both sources are unusable and verify feed summary, raw response, and parser error text never become thread正文.
- [x] 5.7 Add cancellation/generation tests proving a stale Web fallback cannot overwrite a newer refresh, page jump, or continuation load.

## 6. Remove Heuristic Merger and NGA Domain Coupling

- [x] 6.1 Delete `NGAThreadDetailMerger`正文 concatenation, whole-text containment, line units, whitespace/case normalization, global Set deduplication, and end-appending behavior.
- [x] 6.2 Remove `normalizedText` and `structuredForumText` as NGA Parser/Merger contracts after all semantic parser and consumer tests pass.
- [x] 6.3 Move NGA smile filename lookup and other NGA-only resource rules behind the NGA parser, leaving shared semantic nodes source neutral.
- [x] 6.4 Remove or rewrite obsolete tests that assert heuristic concatenated strings, replacing them with semantic order, occurrence, provenance, quality, and source-policy assertions.
- [x] 6.5 Search production code for `ForumContentParser.parse(document.normalizedText)` and equivalent reparsing paths and remove every remaining authoritative use.

## 7. Documentation and Verification

- [x] 7.1 Update ADR-010 to define semantic blocks as reading authority, API-first source policy, whole-document Web fallback, and the evidence gate for any future Reconciler.
- [x] 7.2 Update `docs/context.md`, `CONTEXT.md`, NGA/thread-detail module docs, `docs/todo.md`, and `docs/changelog.md` only for behavior and status changed by this implementation.
- [x] 7.3 Run focused Parser, semantic projector, source-policy, pagination, rendering, snapshot, and privacy tests and record actual pass/fail results.
- [x] 7.4 Run the complete `ForumHubTests` suite on a connected iOS device; if no device is available, leave verification pending rather than substituting a simulator result.
- [x] 7.5 Build the ForumHub Debug scheme for the connected iOS device and run static/diff checks, confirming no debug正文, credentials, temporary Fixtures, or unrelated changes remain.
- [x] 7.6 Manually verify on device a normal API-only thread, image/GIF thread, emoji/quote thread, long/paginated thread, Web fallback Fixture path, Web access denial, and refresh cancellation.

## 8. Post-verification regressions

- [x] 8.1 Add a sanitized real-shape Fixture for the observed `[quote][tid]Topic[/tid]` variant, parse it as a semantic quote without leaking source markup, run focused and complete tests, and verify the affected floor on the connected device.
- [x] 8.2 Add a sanitized real-shape Fixture for the observed unwrapped `<b>Reply to [pid]...` header, separate reply-target metadata from the current reply body and emoji, run focused and complete tests, and verify floor 18 on the connected device.
- [x] 8.3 Add a sanitized real-shape Fixture for the observed `<del class='gray'>` inline HTML, preserve its text without exposing source tags, run focused and complete tests, and verify floor 44 on the connected device.
- [x] 8.4 Preserve the observed `<del class='gray'>` formatting as a source-neutral inline strikethrough node, render it in native reading and snapshots while projecting readable plain text, then rerun focused/full device tests and verify floor 44 visually.

## 9. Verification findings

- [x] 9.1 Preserve unusable API main/reply floors through `ThreadDetailParser`, prove the production Parser → source-policy path requests Web, and retain API floor identity during whole-document fallback.
- [x] 9.2 Offset selected Web block provenance when API and Web representations are combined, and verify every selected block resolves to the `.ngaWeb` representation.
- [x] 9.3 When Web was fetched for another unusable floor, retain valid API content but attach a privacy-safe conflict diagnostic to valid same-floor API/Web semantic differences.
- [x] 9.4 Run focused source-policy/parser tests, complete `ForumHubTests`, Debug device build, strict Rasen validation, diff checks, and rerun `/rasen:verify-change` before shipping.
