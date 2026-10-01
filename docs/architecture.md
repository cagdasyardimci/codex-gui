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
