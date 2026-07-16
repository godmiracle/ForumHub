## ADDED Requirements

### Requirement: Public V2EX nodes display their topics
The V2EX adapter SHALL fetch a non-hot, non-latest channel from its public `/go/<native-node-key>` page and map each valid topic item into a `ForumThread` without requiring a V2EX Token or Web login.

#### Scenario: Browse question-and-answer node
- **WHEN** the user selects the V2EX node whose native key is `qna` and the public node page contains topic items
- **THEN** the feed displays the parsed topics instead of a successful empty list

#### Scenario: Browse second-hand node
- **WHEN** the user selects the V2EX node whose native key is `all4all` and the public node page contains topic items
- **THEN** the feed displays the parsed topics instead of a successful empty list

### Requirement: Node topic parsing uses stable link semantics
The V2EX node-page parser MUST recognize a topic by a local topic anchor whose path contains a numeric `/t/<id>` identifier, regardless of CSS class presence or HTML attribute order, while keeping parsing scoped to topic item containers.

#### Scenario: Topic anchor has no topic-link class
- **WHEN** a topic item contains a valid `/t/<id>` anchor without `class="topic-link"`
- **THEN** the parser returns the topic ID and cleaned title from that anchor

#### Scenario: Topic anchor attributes are reordered
- **WHEN** a valid topic anchor contains additional attributes or places `href` after another attribute
- **THEN** the parser still returns that topic exactly once

#### Scenario: Page has no valid topic items
- **WHEN** a node page contains navigation links but no valid topic anchors inside topic item containers
- **THEN** the parser returns no topics and does not invent a topic from unrelated links

### Requirement: V2EX node pagination remains available
The V2EX adapter SHALL preserve the node page's next-page signal and request later pages using the same native node key and requested page number.

#### Scenario: Node page advertises a next page
- **WHEN** the parsed node page contains a supported next-page marker
- **THEN** the fetch result reports `hasMore` as true
