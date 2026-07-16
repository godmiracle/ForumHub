## Context

`V2EXThreadRepository.fetchThread` currently requests `topics/show.json` and `replies/show.json` concurrently, decodes all replies, and maps them into a linear `[Reply]`. `V2EXMapper` immediately prefers `content_rendered` and runs `normalizedContent`, while `V2EXReplyDTO` does not expose a parent relationship because the V2EX API does not provide one. `Reply` likewise has no optional conversation metadata, and `ThreadDetailReplySection` renders the resulting presentation entries linearly.

The supplied V2EX Polish userscript and the live API response for topic `1227563` establish the usable source convention: replies express targets through `@username`, optionally disambiguated by `#floor`. For example, `@smlcgx #7` targets floor 7 when that floor's author is `smlcgx`; a later `@majiajia` can target the closest preceding reply by that author. This convention is inferential rather than an authoritative server-side parent ID, so the implementation must preserve evidence and degrade without inventing relationships.

The project boundary remains: V2EX-specific extraction belongs in `Data/V2EX`; shared detail UI consumes domain/presentation data and never parses source markup. `ForumPostDocument` remains the reading authority, and the original linear reply list remains the source-order authority.

## Goals / Non-Goals

**Goals:**

- Derive deterministic parent links from V2EX API reply content before lossy normalization.
- Preserve enough evidence to explain whether a link was explicit, inferred, or a mismatch fallback.
- Render each V2EX reply exactly once in a mobile-readable forest while retaining a flat fallback.
- Keep source order, reply identity, full content, media rendering, accessibility text and existing non-V2EX behavior intact.
- Cover the real shapes that produced the observed nested conversation, including cross-page floor references even though the App fetches all replies in one API response.

**Non-Goals:**

- Parsing V2EX topic HTML or adding a Web fallback for relation discovery.
- Claiming inferred links are authoritative V2EX data.
- Implementing V2EX reply submission, thank, ignore, hide or moderation actions.
- Reproducing every configurable behavior of V2EX Polish, especially arbitrary multi-mention nesting.
- Replacing `Reply`/`ForumThread`, changing shared content-block semantics, or introducing a general graph framework.
- Changing snapshot layout in the first slice; snapshots continue to use complete linear replies.

## Decisions

### 1. Extract source references before content normalization

The V2EX mapper will retain the raw `content` used for relationship extraction and separately create the existing semantic content document/body projection. Extraction produces ordered username mentions, optional floor references, and the exact leading reference prefix when present. `content` is preferred because it preserves literal `@username` and `#floor`; `content_rendered` is only a parser-local fallback when raw content is absent.

This is chosen over parsing `Reply.body` in the View because normalization is lossy and would violate the provider boundary. It is also chosen over Web parsing because the real API response already contains the required evidence.

### 2. Add optional generic parent-link metadata without replacing the linear model

`Reply` will gain optional conversation metadata with a default of `nil`. The metadata identifies the resolved parent by stable reply/source-post identity and records the referenced username, referenced floor when present, resolution kind, and any verified leading prefix eligible for visual suppression. Resolution kinds distinguish at least:

- explicit floor and author agreement;
- nearest previous author inference;
- floor/author mismatch followed by nearest-author fallback.

No metadata means root/unresolved. The linear `[Reply]` remains canonical; a small pure forest builder derives root/child presentation nodes on demand.

This is preferred over storing child arrays recursively inside `Reply`, which would duplicate replies and complicate equality, pagination and filtering. It is preferred over a V2EX-only View model carrying raw DTOs because shared UI must not depend on source responses.

### 3. Use a conservative, deterministic resolver

The resolver processes replies once in ascending API order while indexing prior replies by normalized username and by V2EX floor. V2EX floors are assigned from the complete API response position starting at 1 and are used only as evidence; resolved edges point to stable reply identity.

Resolution rules are:

1. A verified `@username + #floor` pair resolves only when that prior floor exists and its author matches the mentioned username case-insensitively.
2. With exactly one usable username mention and no verified floor target, resolve to the nearest preceding reply by that author.
3. If a supplied floor points to another author, retain a mismatch-fallback resolution only when a nearest preceding reply by the mentioned author exists.
4. Multiple mentions resolve only when the evidence selects one unique floor-and-author pair; otherwise the reply remains a root.
5. Missing targets, forward references and self/cyclic edges remain unresolved. A valid self-author reply to an earlier reply is allowed because the parent still precedes the child.

The backward-only constraint makes cycles impossible. A linear scan plus author index avoids repeatedly searching the entire reply list.

This intentionally differs from blindly reproducing the userscript's first-match behavior: ambiguous social mentions should not reshape the conversation without unique evidence.

### 4. Build a forest as presentation data and cap visual indentation

The forest builder consumes the canonical reply array plus resolved parent links, emits roots and children in original source order, and guarantees each reply appears exactly once. A missing parent at build time promotes the reply to a root rather than dropping it.

The V2EX detail screen exposes tree and flat reading modes. Tree mode is the normal V2EX conversation presentation; flat mode remains available as an explicit fallback. Visual indentation is capped at three levels; deeper descendants retain branch styling and parent context without further shrinking the content column.

When only-author mode is active, the existing exact filtering semantics take priority and replies render flat. Reverse mode reverses the root groups while preserving chronological order within each branch; it does not invert parent/child direction. Non-V2EX sources continue through the existing flat path.

### 5. Suppress only a verified leading reference prefix at render time

Tree mode may visually omit a leading `@username` and matching `#floor` only when that exact prefix was consumed as evidence for the resolved parent. The underlying `ForumPostDocument`, `Reply.body`, accessibility value, sharing and snapshots remain complete. References elsewhere in the body, mismatched references and unresolved prefixes remain visible.

This produces the compact V2EX Polish-style conversation without deleting user content or teaching the content parser about conversation layout.

### 6. Verify through pure tests, a real-shape fixture and mobile UI coverage

Parser/resolver/forest builder tests will cover explicit targets, nearest-author inference, repeated authors, mismatched floors, multiple mentions, missing/forward targets, self-author replies, deep nesting and stable ordering. A trimmed and documented fixture based on topic `1227563` will retain the relevant raw shapes without unrelated post content. Mapper tests will prove extraction occurs before normalized rendering.

A focused detail presentation test will prove flat fallback, only-author behavior, reverse root grouping and indentation capping. Full `ForumHubTests`, a connected-device build, and manual verification of the representative `#7 → #24 → #32 → #35 → #38`, `#7 → #42`, and `#42 → #112/#115` branches are required before completion.

## Risks / Trade-offs

- **[Inferred relationship can be wrong]** → Expose resolution kind internally, use conservative ambiguity handling, and always provide flat mode.
- **[API floor position can differ after deletions or hidden replies]** → Require author agreement before treating a floor as explicit evidence; otherwise use a labeled fallback or leave unresolved.
- **[Deep trees reduce phone readability]** → Cap visual indentation and preserve branch indicators beyond the cap.
- **[Existing only-author/reverse behavior can conflict with hierarchy]** → Give exact filtering priority, reverse only root groups, and lock these combinations with presentation tests.
- **[Adding optional metadata touches shared model equality/initializers]** → Use a defaulted optional value, update content-replacement helpers to preserve it, and run all source tests to detect accidental loss.
- **[Visual prefix suppression could hide meaningful text]** → Permit it only for an exact leading prefix verified against the selected parent; never mutate stored content.

## Migration Plan

1. Add pure reference and relation models plus resolver tests without changing UI behavior.
2. Populate V2EX floor numbers and optional relation metadata in the mapper using a documented real-shape fixture.
3. Add the pure forest/presentation builder and integration tests.
4. Add the V2EX tree/flat UI, capped indentation and verified-prefix presentation.
5. Run focused tests, complete `ForumHubTests`, connected-device build and manual topic verification.
6. Update affected ADR, V2EX/thread-detail/testing docs, capability matrix and changelog after behavior is verified.

Rollback is additive: disable/remove V2EX tree presentation and ignore optional relation metadata; the canonical linear replies and complete content documents remain unchanged.

## Open Questions

- The exact control placement for switching tree/flat mode should reuse the existing detail “more” menu unless implementation inspection finds a more consistent shared control.
- Whether tree/flat preference should persist across launches can remain session-local in the first slice unless an existing detail preference store provides a proven, low-cost home.
