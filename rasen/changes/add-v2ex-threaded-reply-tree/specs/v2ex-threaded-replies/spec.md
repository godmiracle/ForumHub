## ADDED Requirements

### Requirement: V2EX references are extracted before normalization
The system SHALL extract reply-target evidence from V2EX API reply content before HTML cleanup, semantic projection, or any visual omission, while preserving the complete original reply content for rendering, sharing and accessibility.

#### Scenario: Raw API reference survives content normalization
- **WHEN** a V2EX API reply contains a leading `@alice #7` reference and rendered content also contains formatting
- **THEN** the mapped reply retains the complete semantic content and exposes the username and floor evidence to the relationship resolver

#### Scenario: Content has no reply reference
- **WHEN** a V2EX API reply contains ordinary text without a usable username mention
- **THEN** the mapped reply remains eligible to display as a root and its content is unchanged

### Requirement: Explicit floor and author evidence takes precedence
The system SHALL resolve an explicit V2EX parent only when the referenced floor precedes the child and the author at that floor matches the referenced username case-insensitively.

#### Scenario: Floor and author agree
- **WHEN** reply 24 contains `@smlcgx #7` and API floor 7 is an earlier reply authored by `smlcgx`
- **THEN** reply 24 links to the stable identity of floor 7 with explicit floor-and-author resolution

#### Scenario: Floor identifies another author
- **WHEN** a reply contains `@alice #7` but API floor 7 was authored by `bob`
- **THEN** floor 7 is not accepted as the explicit parent

#### Scenario: Floor points forward
- **WHEN** a reply references a floor that occurs after the reply in API order
- **THEN** the system does not create an edge to that future reply

### Requirement: Single-mention replies can use nearest-author inference
When a reply has exactly one usable username mention and no verified explicit target, the system SHALL resolve to the nearest preceding reply by that author when one exists and SHALL record that the relation was inferred.

#### Scenario: Repeated author selects nearest previous reply
- **WHEN** multiple earlier replies are authored by `smlcgx` and a later reply contains only `@smlcgx`
- **THEN** the later reply links to the closest preceding `smlcgx` reply rather than the first reply by that author

#### Scenario: User replies to their own earlier message
- **WHEN** a reply authored by `alice` contains `@alice` and an earlier reply by `alice` exists
- **THEN** the later reply may link to the nearest earlier reply by `alice` without creating a cycle

#### Scenario: Mentioned author has no earlier reply
- **WHEN** a reply mentions a username that has no preceding reply in the loaded API sequence
- **THEN** the reply remains unresolved and displays as a root

### Requirement: Conflicting and ambiguous evidence degrades safely
The system MUST NOT invent an arbitrary parent when V2EX reply evidence identifies multiple possible users or cannot be reconciled uniquely.

#### Scenario: Mismatched floor falls back to nearest mentioned author
- **WHEN** a reply contains one username and a floor owned by another author but an earlier reply by the mentioned username exists
- **THEN** the reply links to the nearest earlier reply by that username with mismatch-fallback resolution rather than treating the mismatched floor as authoritative

#### Scenario: Multiple mentions have no unique explicit target
- **WHEN** a reply contains multiple usernames and the evidence does not select exactly one matching earlier floor-and-author pair
- **THEN** the reply remains a root and no mentioned user is chosen arbitrarily

#### Scenario: Multiple mentions contain one unique verified pair
- **WHEN** a reply contains multiple usernames but exactly one username and floor pair identifies the same preceding reply
- **THEN** the system may link to that uniquely verified reply with explicit resolution

### Requirement: Reply forest preserves identity and source order
The system SHALL derive the reply forest from the canonical linear reply array, include every reply exactly once, and preserve API order among roots and among siblings.

#### Scenario: Representative conversation builds the expected branches
- **WHEN** the resolver processes the documented topic shape containing floors 7, 24, 32, 35, 38, 42, 112 and 115
- **THEN** it builds the branches `7→24→32→35→38`, `7→42`, and `42→112/115` without duplicating any reply

#### Scenario: Resolved parent is unavailable to the builder
- **WHEN** a reply carries a parent identity that is absent from the canonical reply array
- **THEN** the builder promotes that reply to a root instead of dropping it

#### Scenario: Deep branch exceeds visual indentation limit
- **WHEN** a branch is deeper than three visual levels
- **THEN** descendants remain in parent-child order with branch context but the content column is not indented beyond the configured cap

### Requirement: V2EX detail supports tree and flat reading
The V2EX thread detail SHALL provide a tree presentation and an explicit flat fallback without changing non-V2EX reply presentation.

#### Scenario: Normal V2EX tree presentation
- **WHEN** tree mode is active for a V2EX thread with resolved parent links
- **THEN** child replies render beneath their parent with mobile-readable branch styling and each reply is visible once

#### Scenario: Flat fallback
- **WHEN** the user selects flat mode
- **THEN** replies render once in the existing linear API order without relation indentation

#### Scenario: Only-author filtering takes priority
- **WHEN** only-author mode is active for a V2EX thread
- **THEN** matching replies retain the existing exact filter behavior and render flat rather than adding nonmatching ancestors

#### Scenario: Reverse tree ordering
- **WHEN** reverse ordering is active while V2EX tree mode is selected
- **THEN** root groups are reversed while parent-child direction and chronological sibling order within each branch remain intact

#### Scenario: Another source is displayed
- **WHEN** the active thread source is NGA or LINUX DO
- **THEN** the existing reply presentation remains unchanged and no V2EX reference parser runs in the View

### Requirement: Visual reference suppression never deletes content
The system SHALL visually suppress a leading V2EX reference only when it exactly corresponds to the resolved parent, and SHALL retain the complete underlying content for accessibility, sharing, snapshots and flat mode.

#### Scenario: Verified leading reference is visually redundant
- **WHEN** tree mode displays a child whose leading `@username #floor` prefix exactly identifies its resolved parent
- **THEN** that prefix may be omitted from the visible tree body while the complete content remains available to all nonvisual consumers

#### Scenario: Reference is unresolved or appears inside the body
- **WHEN** a reference is mismatched, unresolved, or is not the verified leading prefix
- **THEN** the reference remains visible and the system does not remove any text

### Requirement: API-only behavior is fixture-backed and device-verifiable
The implementation SHALL use the existing V2EX API response as its only remote source for reply relationships and SHALL provide automated and connected-device evidence before the change is marked complete.

#### Scenario: Relationship feature loads a thread
- **WHEN** ForumHub fetches a V2EX thread for tree presentation
- **THEN** it uses the existing topic and replies API requests and does not request V2EX topic HTML for relation discovery

#### Scenario: Automated verification
- **WHEN** the implementation is ready for acceptance
- **THEN** focused extractor/resolver/forest/presentation tests and the complete `ForumHubTests` suite pass using documented fixtures

#### Scenario: Representative device verification
- **WHEN** an unlocked iOS device is available for acceptance
- **THEN** the app build and manual verification confirm the representative branches, full reply content, readable deep indentation, flat fallback, only-author mode and reverse mode
