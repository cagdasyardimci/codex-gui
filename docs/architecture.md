# Application architecture

The application uses Model View Intent (MVI) with one canonical workspace store per
checkout/session. AppKit owns windows, controls, focus, selection and layout. Backend
conversation history remains owned by Codex; local stores retain drafts and preferences.

File placement follows [conventions](../CONVENTIONS.md#file-organization-and-ownership).
For the task procedure and documentation routes, see [agent workflow](agent-workflow.md).

## State transitions

`WorkspaceStateStore` owns the model for each checkout/session, including the source session.
Views receive presentations and send intents; they do not decode protocol messages or
edit Codex conversation files. `CodexService` is the application-facing backend interface,
implemented in `CodexClient/`. Cross-feature composition uses standalone composition types.

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

Follow-up conversation reads return through `WorkspaceStoreInputs`, which captures fresh
request identity and clock values. Filesystem-backed checkout validation occurs before
the read is proposed; reducers revalidate that captured ownership against current state.
`ConversationTurnPreview` in `Application/State/` holds canonical compact preview values.
Runtime receives the application service `ConversationPreviewPreparing`; `AppDelegate` injects
the transcript's `ConversationMarkdownPreviewPreparer`. The runner prepares Markdown-to-plain-text
previews off the main actor with cancellation propagation before returning typed results.
Reducers consume these prepared values.

## Ownership and recovery

Execution ownership is independent of the displayed conversation. Results must match
their pending operation, owner and connection generation. Selecting another chat does
not transfer an active turn, approval, command result, draft or deferred callback.

`ExecutionRegistry` retains one execution value per ordinary conversation. An anonymous
submission uses its draft lifetime until preparation assigns a thread ID.
`WorkspaceExecutionScope` routes captured requests and backend thread/turn events through
the existing reducers. Its temporary reduction scope is restored before publication;
`WorkspaceModel.execution` then projects the selected conversation. Aggregate lifecycle
checks inspect every registry entry rather than that selected projection.

Ordinary chats in one checkout share the existing app-server connection and can run
independently. Managed task checkouts keep separate stores, connections and ownership
validation. Both paths reuse the same execution transitions. Per-chat Git baselines and
reported patches retain their owners, while working-tree comparisons describe the shared
checkout and can include other chats' edits.

An interrupted agent turn does not establish command cancellation. Known commands
retain their thread/turn/item identity until explicit terminal evidence arrives.
Uncertain outcomes block checkout cleanup and prevent deferred quitting. Reconnection,
relaunch and incomplete history cannot silently clear these barriers or resend work.

A synchronous local checkpoint records recoverable thread IDs before starting a turn.
Startup restores those IDs alongside unresolved command ownership; reconnect reads every
recoverable thread. A saved running history entry alone does not prove the remote turn is
still active. Recovery adopts a current transport owner only with authoritative live
activity, and never automatically resends the prompt.

`TaskWorkspaceCoordinator` maintains the store registry and executes checkout lifecycle
effects. `WorkspaceCoordinatorReducer` owns selection, creation, recovery, cleanup and
aggregate quit decisions. Git worktree operations revalidate repository, branch, path
and clean-file ownership; removal retains the branch and durable task record.

Shared persistence preserves existing project/thread keys and ordering.

## Presentation

AppKit callbacks dispatch captured `WorkspaceIntentTarget` intents and render narrow read-only presentations.
`WorkspaceEligibility` shares capability rules between selectors and reducers, with admission checked again
when an intent is reduced. Publication is coalesced while all accepted backend events
are processed in order. Transcript preparation runs asynchronously and superseded
renders are cancelled without changing AppKit's ownership of focus and scrolling.

Feature placement follows the [feature map](../Sources/CodexGUI/Features/README.md).
Terminal invocations remain transcript activity and are excluded from the canonical Sources
inventory. Source counts, summary and tab presentation must agree.
Both Sources and transcript attachments use `Features/Shared/SourceThumbnailLoader`.
The shared actor bounds input decoding, prepares pixels off the main actor and reuses decoded
thumbnails. `CodexClient/InlineImageData` handles inline payload identification and bounded
decoding; `Application/Services/LocalAttachmentURL` resolves local paths and file URLs.
The thumbnail `NSCache` is configured for 64 entries and 16 MiB of estimated pixel/key cost,
separate from workspace content residency. File reads and decoded inline payloads are bounded
to 32 MiB; maximum image dimensions are 80 pixels for Sources, 320 for transcript thumbnails
and 1600 for inline previews. AppKit views retain generation checks and cancellation on reuse.

Pure reported-patch composition belongs to `Application/Reducers/Review/ConversationNetFileChanges`.
`ConversationNetFileChangePreparation` prepares those results off the main actor and retains
exact inputs and outputs for reuse within the same transcript context. Its reusable cache
defaults to 256 entries and 8 MiB. `TranscriptPreparationCoordinator` publishes prepared text,
navigation summaries and net file changes together only for the accepted render generation.
Current resident content can produce results larger than the reusable cache budget; those
results are available to the current render without entering that cache. Folded completed
work defers hidden message preparation until disclosure or navigation reveals it.

See [conventions](../CONVENTIONS.md) for source ownership and test organization, and
[validation](validation.md) for verification commands and acceptance limits.

## Recorded latest Git turn

`ConversationReportedGitTurn` in `Application/Reducers/Conversation/` retains the known latest
editing turn's identity and available timestamps independently of loaded transcript bodies.
`ConversationReportedGitTurnProjection` in `Application/Presentation/` resolves that identity
against currently resident reported changes. Missing or evicted payload is unavailable;
an authoritative completed file-change report containing no changes produces an empty result.
Older loaded edits cannot replace a known later editing turn without trusted ordering evidence.

All conversation View changes actions continue to open the shared latest-edit Last Turn
comparison. The recorded identity does not retain a separate unbounded patch cache. When its
reported payload is unavailable, the comparison retains its captured-baseline fallback and
explicit unavailability behavior.

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
