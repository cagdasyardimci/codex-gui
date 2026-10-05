# Application architecture

The application uses Model View Intent (MVI) with one canonical workspace store per
checkout/session. AppKit owns windows, controls, focus, selection and layout. Backend
conversation history remains owned by Codex; local stores retain drafts and preferences.

## State transitions

`WorkspaceModel` contains feature values for connection, execution, the composer,
conversations, review, navigation, preferences, usage and workspace lifecycle.
`WorkspaceStoreInputs` captures the owner/session, connection generation and request
identity before proposing typed actions. Reducers synchronously change values and
describe effects. They do not call the backend, access storage, schedule tasks, read
clocks or generate identifiers. Cross-feature domain events are composed before
publication so observers receive a coherent snapshot.

`WorkspaceEffectRunner` performs backend, filesystem and persistence operations and
returns scoped results. Accepted work is reserved before observers are notified.
Runtime jobs, subscriptions, task handles and waiters remain outside model state.
Persistence scheduling preserves accepted-write order and supports draining writes
before checkout removal or application termination.

## Ownership and recovery

Execution ownership is independent of the displayed conversation. Results must match
their pending operation, owner and connection generation. Selecting another chat does
not transfer an active turn, approval, command result, draft or deferred callback.

An interrupted agent turn does not establish command cancellation. Known commands
retain their thread/turn/item identity until explicit terminal evidence arrives.
Uncertain outcomes block checkout cleanup and prevent deferred quitting. Reconnection,
relaunch and incomplete history cannot silently clear these barriers or resend work.

`TaskWorkspaceCoordinator` maintains the store registry and executes checkout lifecycle
effects. `WorkspaceCoordinatorReducer` owns selection, creation, recovery, cleanup and
aggregate quit decisions. Git worktree operations revalidate repository, branch, path
and clean-file ownership; removal retains the branch and durable task record.

## Presentation

AppKit callbacks dispatch captured intents and render narrow read-only presentations.
Capability rules are shared by selectors and reducers, with admission checked again
when an intent is reduced. Publication is coalesced while all accepted backend events
are processed in order. Transcript preparation runs asynchronously and superseded
renders are cancelled without changing AppKit's ownership of focus and scrolling.

See [conventions](../CONVENTIONS.md) for source ownership and test organization, and
[validation](validation.md) for verification commands and acceptance limits.


## Conversation content residency

`ConversationCachePolicy` defines the defaults used by the backend and conversation UI:

| Resource | Limit |
| --- | --- |
| Initial and older full-content pages | 25 turns |
| Hover and unloaded navigation debounce | 75 ms |
| Reading neighborhood | 25 known references around the viewport anchor |
| Retained full turns | 75 per chat |
| Shared content payload budget | 32 MiB per workspace store, across its chats |
| Compact previews | 200 entries and 1 MiB per workspace store |
| Hover-only full bodies | 3 entries, 2 MiB shared, 15-second reuse lifetime |
| Hover backend traversal | First and last item pages, at most 100 items each |

These byte costs estimate decoded textual payload and retained entry bodies, not total
process memory or AppKit attributed strings, images and layout overhead. Visible turns,
the reading anchor, the pending jump target and a live execution turn are protected.
Protected oversized content may exceed the budget; background neighborhood fetching
then pauses. Hover-only bodies are discarded before transcript content. Unprotected
full turns and compact previews use least-recently-used eviction.

Viewport publication is debounced and scoped to the presentation owner. Neighbor reads
run serially and queued targets follow the current anchor. Foreground navigation
supersedes background neighborhood reads; the runner retains at most one local read
in each role (navigation, preview, neighborhood). Preview reads do not change transcript
entries or reading position. A click promotes an existing preview fetch; incomplete
boundary-page previews require a subsequent full-content read before navigation.

Evicted turns retain metadata references. Visible missing ranges receive explicit gap
markers and are hydrated as the reader approaches them. Jump resolution excludes gap
markers. Existing reading-anchor restoration preserves message identity and pixel offset
when entries are removed or inserted. The Latest action targets the latest rail turn,
including when its contents were evicted. Manual transcript wheel input supersedes a
pending rail navigation or its animation; wheel input on the rail remains independent.

Completion/error responses remain guarded by workspace, connection generation, thread,
request identity and command revision. Backend mutations invalidate cached previews for
the affected turn. Expiration is scheduled by the runtime; reducer cache time is supplied
by timestamped actions so eviction remains deterministic in tests.
