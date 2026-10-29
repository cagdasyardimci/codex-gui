# Application architecture

This guide records boundaries and invariants that changes must preserve. Use [conventions](../CONVENTIONS.md#file-organization-and-ownership) for placement rules and the [application source](../Sources/CodexGUI/Application/) for concrete models, transitions and effect implementations.

## State transitions

The application uses Model View Intent (MVI) with one canonical store per checkout/session. Views render presentations and send intents; reducers synchronously change values and describe effects. Backend, filesystem and persistence work belongs to runtime services. Keep task handles, subscriptions and native view state outside the canonical model. Supply clocks and identifiers through captured actions rather than creating them in reducers.

Compose cross-feature transitions before publication and reserve accepted effects before notifying observers. Otherwise observers can see partially applied transitions or submit conflicting work. Persistence must preserve accepted-write order and support draining before checkout removal or termination.

Backend history belongs to Codex. Local persistence owns drafts, preferences and recovery records; views must not edit Codex conversation files. Capture next-turn preferences at submission so later control changes cannot retarget accepted work. Settings-specific persistence follows [Settings](settings.md#configuration-ownership).

## Ownership and recovery

Displayed selection and execution ownership are independent. Every asynchronous result must validate its captured workspace/session, connection generation, request identity and relevant thread/turn. Deferred UI actions must retain their original target rather than follow later selection. Shared eligibility rules serve presentations and reducers, with admission checked again at reduction.

Ordinary chats share their checkout and app-server while retaining independent execution state. Managed task checkouts have separate stores and connections. Cleanup and quit decisions must inspect all executions, including hidden chats. A working-tree comparison can contain edits from several chats.

An interrupted turn does not prove command cancellation. Retain known command identities until authoritative terminal evidence arrives. Disconnects, relaunches and incomplete history must not clear uncertain outcomes or automatically resend possibly accepted work. Recovery records must become durable before starting a turn. Saved running history alone is insufficient evidence to adopt live execution ownership.

Distinguish a known rejection from an uncertain submission. A cross-app writer lock is a known rejection; reading its saved history must not adopt another client's turn. Retry reestablishes ownership without resending the prompt. Preserve submitted drafts until acknowledgement, restoring them only if the resulting empty draft remains untouched; newer edits and independent draft lifetimes take precedence.

The first message starts a turn; only an active turn with an accepted turn identity can queue follow-ups. Queues belong to their original conversation. On servers supporting the experimental queue API, the server owns durable ordering and automatic dispatch; the GUI refreshes every page after invalidations and never runs a competing dispatcher. Checkout ownership and connection generation scope every operation. Stable client identities, persisted acceptance journals and server receipts prevent automatic replay after uncertain writes or relaunch. Local queues remain available when the server explicitly rejects the read API; older local buffers migrate only after Resume because adding to an idle server may immediately start work. Queue persistence shares ordered draft writes and attachment ownership, and consumed entries transfer their attachments to conversation references before removal. Interruptions, failures and disconnects preserve pending follow-ups paused; restored queues also require explicit Resume. Resume starts a pending input as a new turn, with a queue-level action and an empty-composer action. Reordering and editing retain identity and reject stale or reserved entries. Editing uses the normal composer without overwriting an occupied draft; consumption of an edited server entry preserves its unsent draft. Per-row steering captures the active turn and, for server-owned entries, requires confirmed deletion before steering the original encoded input. A durable handoff journal prevents replay after lost replies or relaunch; ambiguous deletion or steering outcomes remain reserved for reconciliation, while a definitive steering rejection retains the detached input for explicit recovery. Turning queueing off routes new active-turn follow-ups through ordinary steering; its preference is conversation-scoped. Captured model, effort, permissions, collaboration mode and service tier remain sidecar metadata for server-owned entries because queue requests encode input only; automatic server dispatch uses server thread settings. See [server queue effects](../Sources/CodexGUI/Application/Runtime/WorkspaceEffectRunner/WorkspaceEffectRunner+ServerQueue.swift) for reconciliation and migration.

Shared persistence and cross-project navigation must preserve project/thread identities. Matching titles, paths or visible selection cannot substitute for those identities. Archive, deletion and checkout removal must revalidate their captured targets and report partial success without replaying confirmed mutations.

Protocol-specific handling belongs to [CLI lifecycle safeguards](cli-compatibility.md#protocol-lifecycle-safeguards); deferred native confirmations follow [AppKit conventions](../CONVENTIONS.md#appkit-behavior-and-accessibility).

## Presentation

AppKit owns focus, selection, scrolling and layout. Prepare parsing, file reads and expensive derived content away from the main actor, then install only the current render generation. Cancellation and owner retirement must reject stale installation and dismiss transient UI. Reuse must preserve the reader's position and selection within one owner without carrying them into another conversation.

Keep shared rendering separate from consumer lifetimes: a renderer owns its resource limits and output; its feature owns loading, cancellation and presentation. Preserve exact source identity for selection, copy and caching, including byte-distinct paths and Unicode spellings. Unsupported or over-budget rich content must retain readable source. Filesystem reads and writes must remain contained, bounded and cancellable; revision conflicts must preserve unsaved edits.

Do not duplicate canonical payload inventories in presentation caches. Sources, transcript activity and summaries may project the same records differently, but must agree on identity and outcomes. Activity-specific design decisions belong to [activity presentation](activity-presentation-design.md), and native adaptation rationale belongs to [interface styling](interface-styling.md#native-adaptation-rationale).

## Recorded latest Git turn

Last Turn attributes reported edits to the selected task's turn. Checkout-wide diffs cannot establish that attribution when chats interleave edits, even to the same file. Retain the latest known editing-turn identity independently of resident transcript bodies; older loaded edits cannot replace it without trusted ordering evidence.

Missing or evicted reports differ from an authoritative empty report. Never substitute another turn's viewer snapshot or a working-tree diff for unavailable reports. Exact patch composition may cancel compatible reversals; incompatible or over-budget sequences retain reported patches without offering them as an applicable combined patch. Filter reports to the owning checkout without merging byte-distinct filenames.

Shell writes and child-thread edits require backend attribution before they can be assigned to a parent turn. Shared directories, filenames and timing are insufficient evidence. Isolated task checkouts or backend write attribution are required for complete coverage. The recorded turn identity must not become a second unbounded patch cache.

The [review reducers](../Sources/CodexGUI/Application/Reducers/Review/) and [review runtime](../Sources/CodexGUI/Application/Runtime/Review/) define composition and comparison behavior; [presentation](../Sources/CodexGUI/Application/Presentation/) defines counts and badge projections.

## Conversation content residency

Residency bounds retained conversation payload, rather than total process memory. Native attributed strings, image decoding and layout overhead have separate owners. Protected visible or active content may exceed the payload budget; background fetching must yield rather than evict that content.

Eviction must preserve navigation metadata and reading anchors. Preview reads cannot change transcript entries or reading position. Foreground navigation supersedes neighborhood work; owner changes and manual transcript scrolling cancel obsolete navigation. Keep all residency defaults and cost estimates in [ConversationCachePolicy](../Sources/CodexGUI/Application/State/ConversationCachePolicy.swift), rather than copying limits into consumers or documentation.
