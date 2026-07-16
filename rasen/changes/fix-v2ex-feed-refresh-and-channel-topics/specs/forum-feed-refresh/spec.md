## ADDED Requirements

### Requirement: Feed supports pull-to-refresh
The system SHALL allow the user to pull down on the actual Home or Hot feed scrolling surface to reload the first page for the active source, tab, channel, sort, and filter context.

#### Scenario: Refresh current V2EX channel
- **WHEN** the user pulls down on a loaded V2EX channel feed
- **THEN** the system invokes the existing first-page reload for that same channel and displays the refreshed topics

#### Scenario: Refresh short V2EX hot feed
- **WHEN** V2EX “最热” is the active Home channel and its content is too short to scroll naturally
- **THEN** the actual feed surface still permits a downward refresh gesture and invokes the existing first-page reload

#### Scenario: Refresh gesture completes
- **WHEN** a pull-to-refresh request succeeds, fails, or is superseded by a newer feed request
- **THEN** the system ends the refresh presentation without allowing a stale response to overwrite the current feed context

### Requirement: Pull-to-refresh coexists with feed navigation
The system MUST preserve vertical scrolling, horizontal channel paging, thread navigation, and the existing explicit refresh button while pull-to-refresh is enabled.

#### Scenario: Horizontal channel swipe
- **WHEN** the user performs a qualifying horizontal swipe in the feed
- **THEN** the system switches channel according to the existing paging policy rather than treating it as a refresh

### Requirement: Restored default channel is selected at launch
The system SHALL initialize the active forum summary and channel selection from the persisted source's Repository default before the first asynchronous reload.

#### Scenario: Relaunch with V2EX persisted
- **WHEN** the persisted active source is V2EX and the app is recreated
- **THEN** V2EX “最热” is the active forum and its channel control is selected from the first rendered state

### Requirement: V2EX hot continues with more recent topics
The system SHALL preserve V2EX's official daily hot topics as the first page and SHALL load the PC site's `/recent` continuation when the user reaches the bottom of the left-top “最热” channel.

#### Scenario: Scroll to the end of V2EX hot
- **WHEN** the user scrolls the V2EX “最热” channel near the end of its first page
- **THEN** the feed displays the existing loading-more state and appends unique topics from `/recent?p=1`

#### Scenario: Continue after the first recent page
- **WHEN** the first recent continuation advertises another page
- **THEN** the next hot continuation requests the next `/recent` page without stale writes or duplicate topic IDs

#### Scenario: Aggregated topics retain their real nodes
- **WHEN** a hot or recent topic identifies its source node
- **THEN** the row displays that real node rather than labeling the topic itself as belonging to the virtual “最热” channel

#### Scenario: Home hot matches the bottom hot tab
- **WHEN** the same V2EX hot payload is displayed through the Home “最热” channel and the bottom “热门” tab
- **THEN** both paths preserve the same topic identities, order, and real node labels
