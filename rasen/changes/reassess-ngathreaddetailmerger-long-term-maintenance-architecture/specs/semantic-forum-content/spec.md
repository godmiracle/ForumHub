## ADDED Requirements

### Requirement: Semantic document is the content authority
The system SHALL represent every thread post and reply with a semantic content document containing ordered content blocks, source representations, parser diagnostics, and a content schema version. Stored or computed plain text MUST NOT replace the ordered content blocks as the authoritative reading representation.

#### Scenario: Parsed post becomes a semantic document
- **WHEN** a source parser successfully parses a post containing text, an image, and a quote
- **THEN** the resulting document contains ordered semantic blocks for the text, image, and quote and retains the source representation used to produce them

#### Scenario: Plain text cannot overwrite semantic content
- **WHEN** a consumer requests the legacy `body` or normalized text value
- **THEN** the system derives that value from the semantic blocks without mutating the blocks or source representations

### Requirement: Source representations remain traceable
The system SHALL retain each selected or attempted source representation with its origin, markup format, raw markup, source URL when available, and schema/parser version. A document assembled from more than one observation MUST NOT claim that one raw markup value alone represents all semantic content.

#### Scenario: Web fallback retains both observations
- **WHEN** an unusable API content observation is replaced by a valid Web content observation
- **THEN** the final document retains both source representations and identifies the Web representation as the selected semantic source

### Requirement: Parsers produce semantic content directly
Each source markup dialect SHALL have a source-specific parser that converts raw markup into semantic blocks and diagnostics without using a lossy plain-text projection as an intermediate contract. Syntax AST or DOM types MUST remain internal to the parser layer.

#### Scenario: NGA BBCode parsing
- **WHEN** an NGA API post contains nested BBCode, images, quotes, emoji, and text
- **THEN** the NGA BBCode parser emits ordered semantic blocks and does not expose BBCode syntax nodes to Domain or Feature code

#### Scenario: Web HTML parsing
- **WHEN** an NGA Web `postcontent<floor>` node contains nested HTML and NGA markup
- **THEN** the NGA HTML parser emits the same semantic node types used by the API parser while keeping DOM details private

### Requirement: Unknown content degrades without silent deletion
The parser SHALL preserve unsupported or malformed source fragments as an explicit unsupported semantic node or a safe fallback representation and SHALL emit a diagnostic. Unknown content that can be displayed safely MUST be classified as degraded rather than unusable.

#### Scenario: Unknown BBCode tag
- **WHEN** a post contains an unrecognized BBCode tag with user-visible text
- **THEN** the text remains visible through an unsupported or fallback node and a non-fatal diagnostic identifies the unknown tag

#### Scenario: Fatal parse failure
- **WHEN** a parser cannot recover any safe user-visible content from a non-empty source representation
- **THEN** it returns an unusable quality result with a fatal diagnostic instead of an empty successful document

### Requirement: Content nodes are source neutral
Shared semantic content nodes SHALL NOT depend on NGA-specific DTOs, smile tables, HTML elements, or BBCode tags. Source adapters MUST map source-specific resources into generic image, emoji, link, quote, and text values before returning a semantic document.

#### Scenario: NGA emoji mapping
- **WHEN** the NGA parser resolves a known `[s:...]` token
- **THEN** it returns a generic emoji resource with URL and accessibility label and the shared Domain does not expose an `NGAForumSmile` dependency

### Requirement: Ordered duplicates are preserved
The semantic document SHALL preserve the source order and occurrence count of content nodes. Display identity MUST distinguish separate occurrences even when their payloads or canonical URLs are equal.

#### Scenario: Repeated image is intentional
- **WHEN** the source document contains the same canonical image URL in two different positions
- **THEN** the semantic document contains two image occurrences in their original positions

#### Scenario: Repeated paragraph is intentional
- **WHEN** the source document contains two identical paragraphs separated by other content
- **THEN** both paragraphs remain present and have distinct display identities

### Requirement: All content consumers use semantic projectors
Native reading, plain-text/body projection, image enumeration, long-image rendering, sharing, accessibility text, and content signatures SHALL derive from the same semantic document. Consumers MUST NOT reparse `normalizedText` or raw source markup.

#### Scenario: Reading and snapshot agree
- **WHEN** a semantic document contains text, an emoji, a quote, and two images
- **THEN** native reading and snapshot rendering traverse the same ordered nodes and expose the same two content images

#### Scenario: Plain-text projection
- **WHEN** a consumer requests share text or a body preview
- **THEN** the plain-text projector returns a deterministic readable projection without changing semantic node order or source representations

### Requirement: Diagnostics protect user content and credentials
Parser and projection diagnostics SHALL use structured codes and MAY include source, floor, parser version, and counts. Release diagnostics MUST NOT include raw markup, rendered正文, Cookie, Token, guest token, or other credentials.

#### Scenario: Release parse warning
- **WHEN** a release build encounters an unknown NGA tag
- **THEN** telemetry or logs contain only the structured diagnostic metadata and do not contain the post text or authentication state
