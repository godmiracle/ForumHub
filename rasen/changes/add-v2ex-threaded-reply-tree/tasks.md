## 1. Fixtures and executable contract

- [x] 1.1 Add a documented, trimmed V2EX reply fixture based on topic `1227563` that preserves floors 7/24/32/35/38/42/112/115, repeated-author, mismatch, multi-mention and unresolved reference shapes without unrelated user content.
- [x] 1.2 Add failing focused tests for raw reference extraction, explicit floor-author agreement, nearest-author inference, mismatch fallback, ambiguity, missing/forward targets and self-author replies.

## 2. Source mapping and relationship resolution

- [x] 2.1 Add defaulted optional reply-conversation metadata and resolution kinds to the shared domain model, and ensure content replacement/equality paths preserve the metadata without changing existing source constructors.
- [x] 2.2 Implement the V2EX-only raw reference extractor before `normalizedContent`, including exact leading-prefix evidence and safe `content_rendered` fallback behavior.
- [x] 2.3 Implement the pure, backward-only V2EX relationship resolver with prior-author/floor indexes and conservative multi-mention handling.
- [x] 2.4 Update `V2EXMapper.threadDetail` to assign one-based API floor numbers, resolve stable parent identities, preserve complete content, and satisfy the focused mapper/resolver tests.
- [x] 2.5 Add regression tests proving the V2EX relationship path uses the existing API data only and that NGA/LINUX DO mapping remains unchanged.

## 3. Reply forest and presentation semantics

- [x] 3.1 Add failing tests for a pure forest builder covering the representative branches, source-ordered roots/siblings, missing-parent promotion, one-occurrence identity and deep nesting.
- [x] 3.2 Implement the forest builder as derived presentation data over canonical linear replies, with no recursive duplication inside `Reply`.
- [x] 3.3 Extend thread-detail presentation derivation for V2EX tree/flat mode, exact flat only-author behavior, reversed root groups with chronological branches, and a three-level visual indentation cap.
- [x] 3.4 Add presentation regression tests for tree/flat switching, only-author, reverse ordering, non-V2EX isolation and unchanged canonical reply order.

## 4. Mobile thread-detail UI

- [x] 4.1 Add a V2EX-only tree/flat reading control using the existing detail control conventions, with tree as the normal mode and a reversible flat fallback.
- [x] 4.2 Render parent/child branch styling, avatars, floor labels, actions, rich content and media while keeping every reply visible exactly once and maintaining readable width beyond three levels.
- [x] 4.3 Implement verified leading-reference visual suppression as a presentation projection only; retain full `ForumPostDocument`, accessibility text, sharing, snapshots, flat mode and unresolved references.
- [x] 4.4 Add focused UI/presentation coverage for branch layout identifiers, capped indentation, verified-prefix behavior and fallback behavior.

## 5. Verification and documentation

- [x] 5.1 Run and pass the focused V2EX extractor, resolver, mapper, forest and thread-detail presentation tests.
- [x] 5.2 Run and pass the complete `ForumHubTests` suite without deleting or weakening existing tests.
- [x] 5.3 Build the Debug app for an available connected iOS device using the project-prescribed destination command.
- [x] 5.4 Install on an unlocked device and manually verify topic `1227563`: branches `7→24→32→35→38`, `7→42`, `42→112/115`, full content/media, capped deep indentation, flat fallback, only-author mode and reverse mode; continue fixing any failure before marking complete.
- [x] 5.5 Update affected ADR, `docs/modules/v2ex.md`, `docs/modules/thread-detail.md`, testing/fixture documentation, feature matrix, changelog and `docs/todo.md` only after the verified behavior matches the specification.
- [x] 5.6 Run Rasen validation, `git diff --check`, inspect the complete diff for unrelated/generated/sensitive files, and leave the change incomplete if any required automated or device evidence is missing.
