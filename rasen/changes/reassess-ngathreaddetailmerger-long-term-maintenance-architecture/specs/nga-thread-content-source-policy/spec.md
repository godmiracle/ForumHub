## ADDED Requirements

### Requirement: NGA thread detail is API first
The NGA thread-detail repository SHALL fetch and parse the API response before deciding whether Web content is required. When API content quality is valid or degraded, the repository MUST return the API result without issuing a Web content request.

#### Scenario: Complete API detail
- **WHEN** the API returns usable metadata and semantic content for all posts on the requested page
- **THEN** the repository returns the API-assembled detail and performs no Web detail request

#### Scenario: Recoverable unknown API tag
- **WHEN** the API parser preserves an unknown tag through safe fallback content and classifies the result as degraded
- **THEN** the repository returns the API document and does not request Web solely because of that warning

### Requirement: API fields are authoritative when available
The system SHALL use NGA API root and post fields as the authority for thread title, author, post ID, floor number, timestamp, pagination, reply order, reply count, and attachment metadata. The API mapper MUST consume applicable root-level fields such as `tsubject`, `tauthor`, `vrows`, `currentPage`, `totalPage`, and `attachPrefix` rather than relying on Web to compensate for omitted nested fields.

#### Scenario: Empty first-post subject with root title
- **WHEN** the first API post has an empty `subject` and the root response has a non-empty `tsubject`
- **THEN** the assembled thread uses `tsubject` without requesting Web for title recovery

#### Scenario: Web and API metadata disagree
- **WHEN** both sources are available and their author, timestamp, floor, or ordering metadata differ
- **THEN** the resolved detail retains the API metadata and Web can affect only content selected by the fallback policy

### Requirement: Web fallback requires an unusable API content result
The repository SHALL request Web content only when the API request or API content parser returns an unusable result for required user-visible content. The decision MUST use structured parser/transport status and MUST NOT use fuzzy text similarity, whole-document substring comparison, or arbitrary whitespace differences.

#### Scenario: Empty API floor content
- **WHEN** an API floor is present with stable identity but its non-empty raw representation cannot produce any safe visible content
- **THEN** the repository requests Web and attempts to resolve the same floor from `postcontent<floor>`

#### Scenario: API transport failure
- **WHEN** the API transport fails before stable metadata can be recovered
- **THEN** the repository may attempt a Web-only readable fallback but does not invent API post IDs, authors, timestamps, or pagination metadata

#### Scenario: Both sources unusable
- **WHEN** API content is unusable and Web is unavailable, access denied, or also unusable
- **THEN** the repository returns a typed thread-detail error without replacing正文 with a feed summary or parser error text

### Requirement: Web fallback selects a whole semantic document
When Web fallback succeeds for an API-confirmed floor, the system SHALL select the complete Web semantic document for that floor while retaining API metadata and both source representations. It MUST NOT concatenate, split, deduplicate, lowercase, or reorder plain-text lines from the two sources.

#### Scenario: Web supplies an unusable API floor
- **WHEN** API metadata identifies a floor whose content is unusable and Web provides valid semantic content for the same floor
- **THEN** the resolved floor uses the ordered Web semantic blocks, retains the API floor identity, and records both representations

#### Scenario: Both documents valid but different
- **WHEN** API and Web both produce valid semantic documents that differ in formatting or content
- **THEN** the system keeps the API document, records a non-sensitive conflict diagnostic, and does not automatically merge the documents

### Requirement: Web does not alter API reply membership or order
When API metadata is available, Web fallback MUST NOT add Web-only replies, remove API replies, change reply order, or infer reply identity from body similarity. Web content may replace only a floor that can be matched by an API-confirmed floor number or stable post identity.

#### Scenario: Web contains an extra floor
- **WHEN** Web contains a reply floor absent from the API page result
- **THEN** the resolved API-backed page does not add that Web-only reply and emits a diagnostic suitable for Fixture investigation

#### Scenario: Same floor receives Web content
- **WHEN** API confirms floor 11 but its content is unusable and Web has `postcontent11`
- **THEN** the resolved reply keeps the API post ID, author, timestamp, floor, and order while using the Web semantic content

### Requirement: Heuristic normalized-text merging is removed
The production NGA detail path MUST NOT use `normalizedText` containment, newline units, global content sets, case folding, whitespace deletion, or canonical image URL equality to construct a combined post body. Plain text SHALL remain a downstream projector only.

#### Scenario: Duplicate content occurrences
- **WHEN** a selected source contains the same paragraph or image multiple times
- **THEN** every source occurrence remains present and no global deduplication removes it

#### Scenario: Supplemental content position
- **WHEN** source content contains a node between two paragraphs
- **THEN** its position comes from the selected semantic document and is never moved to the end by a merger

### Requirement: Cancellation and fallback errors remain isolated
Starting a newer thread-detail load SHALL cancel or invalidate the older API/Web strategy execution. A late Web fallback MUST NOT overwrite content from a newer request generation.

#### Scenario: Refresh during Web fallback
- **WHEN** a refresh starts while an older request is waiting for Web fallback
- **THEN** the older fallback result cannot commit thread content or error state after the new generation begins

### Requirement: Reconciliation requires new evidence and a separate change
A dual-source semantic reconciler MUST NOT be introduced by this capability unless separate approved specifications are supported by at least two脱敏真实 paired Fixtures showing that API and Web each contain indispensable content for the same floor and whole-document fallback loses user-visible information.

#### Scenario: One synthetic enrichment Fixture exists
- **WHEN** only artificial or deliberately cropped enrichment Fixtures demonstrate complementary content
- **THEN** the system retains API-first whole-document fallback and does not add automatic semantic reconciliation

#### Scenario: Evidence threshold is reached
- **WHEN** the required real paired Fixtures demonstrate indispensable complementary content
- **THEN** the team creates a separate proposal defining reconciliation identity, ordering, conflict, provenance, and rollback behavior before implementation

### Requirement: NGA source diagnostics are privacy safe
Source-policy diagnostics SHALL record structured source outcome, floor, parser version, and fallback reason without raw正文, raw markup, Cookie, Token, guest token, or user-identifying payloads.

#### Scenario: Web fallback is triggered
- **WHEN** API content is unusable and the repository attempts Web fallback
- **THEN** diagnostics identify the typed fallback reason and outcome without logging the content or session credentials
