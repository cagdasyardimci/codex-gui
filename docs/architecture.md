# Application architecture

The application uses Model View Intent (MVI) with one canonical workspace store per checkout/session. AppKit owns windows, controls, focus, selection and layout. Backend conversation history remains owned by Codex; local stores retain drafts and preferences. Local user rows remain visible until a matching server user item replaces them in place. Matching uses the accepted turn, displayed text and attachment paths; identical messages in other turns or with different server item IDs remain separate.

File placement follows [conventions](../CONVENTIONS.md#file-organization-and-ownership). For the task procedure and documentation routes, see [agent workflow](agent-workflow.md).

## State transitions

`WorkspaceStateStore` owns the model for each checkout/session, including the source session. Views receive presentations and send intents; they do not decode protocol messages or edit Codex conversation files. `CodexService` is the application-facing backend interface, implemented in `CodexClient/`. Cross-feature composition uses standalone composition types.

`WorkspaceModel` contains feature values for connection, execution, the composer, conversations, review, navigation, preferences, usage and workspace lifecycle. `WorkspaceStoreInputs` captures the owner/session, connection generation and request identity before proposing typed actions. Reducers synchronously change values and describe effects. They do not call the backend, access storage, schedule tasks, read clocks or generate identifiers. Cross-feature domain events are composed before publication so observers receive a coherent snapshot.

`WorkspaceEffectRunner` performs backend, filesystem and persistence operations and returns scoped results. Accepted work is reserved before observers are notified. Runtime jobs, subscriptions, task handles and waiters remain outside model state. Persistence scheduling preserves accepted-write order and supports draining writes before checkout removal or application termination.

Follow-up conversation reads return through `WorkspaceStoreInputs`, which captures fresh request identity and clock values. Filesystem-backed checkout validation occurs before the read is proposed; reducers revalidate that captured ownership against current state. `ConversationTurnPreview` in `Application/State/` holds canonical compact preview values. Runtime receives the application service `ConversationPreviewPreparing`; `AppDelegate` injects Conversation's `ConversationMarkdownPreviewPreparer`. The runner prepares Markdown-to-plain-text previews off the main actor with cancellation propagation before returning typed results. Reducers consume these prepared values. Loaded and compact turn previews use the visible user request as their title. The turn card parses title Markdown before styling links, keeps one favicon per visible link, and allows URL characters to wrap within two title lines. Image-only requests use attachment labels, preserving generated composer descriptions when available and falling back to image names. A compact preview retains its bounded reply source only when it contains a web address, so the turn card can recover labeled Markdown links; the source counts toward preview residency costs. These bounded labels remain separate from the thumbnail-only message body and count toward transcript residency costs.

## Ownership and recovery

Accepted message submissions clear the matching editable draft before backend preparation or
acknowledgement. The composer retains the submitted snapshot and the exact resulting empty draft.
Failures, cancellation before sending and disconnect restore the submitted text and attachments
only while that empty draft is untouched and the submission remains unacknowledged. Newer edits
and independent New Chat lifetimes survive late results. Untouched submitted drafts remain stored
until acknowledgement; accepted references become durable before their stored drafts are cleared.

Source selections and code previews share logical lines in UTF-16 coordinates. LF, CRLF, CR, U+2028 and U+2029 each end one line; CRLF counts once, and a terminal separator retains an empty final document line. Selected code excerpts preserve their original separators and blank source lines within inclusive line bounds. Omitting the final selected line's terminator does not remove selected leading or trailing blank lines. Outgoing descriptions use LF between numbered lines. A missing first line defaults to 1, and a missing last line is derived from the first line and excerpt line count; explicitly supplied bounds are preserved.

Execution ownership is independent of the displayed conversation. Results must match their pending operation, owner and connection generation. Selecting another chat does not transfer an active turn, approval, command result, draft or deferred callback. Full Access confirmation retains its requesting workspace and callback: unmodified Return or keypad Enter confirms, and Escape cancels.

`ExecutionRegistry` retains one execution value per ordinary conversation. An anonymous submission uses its draft lifetime until preparation assigns a thread ID. `WorkspaceExecutionScope` routes captured requests and backend thread/turn events through the existing reducers. Its temporary reduction scope is restored before publication; `WorkspaceModel.execution` then projects the selected conversation. Aggregate lifecycle checks inspect every registry entry rather than that selected projection.

Ordinary chats in one checkout share the existing app-server connection and can run independently. Managed task checkouts keep separate stores, connections and ownership validation. Both paths reuse the same execution transitions. Per-chat Git baselines and reported patches retain their owners, while working-tree comparisons describe the shared checkout and can include other chats' edits.

An interrupted agent turn does not establish command cancellation. Known commands retain their thread/turn/item identity until explicit terminal evidence arrives. Uncertain outcomes block checkout cleanup and prevent deferred quitting. Reconnection, relaunch and incomplete history cannot silently clear these barriers or resend work.

A synchronous local checkpoint records recoverable thread IDs before starting a turn. Startup restores those IDs alongside unresolved command ownership; reconnect reads every recoverable thread. A saved running history entry alone does not prove the remote turn is still active. Recovery adopts a current transport owner only with authoritative live activity, and never automatically resends the prompt.

`TaskWorkspaceCoordinator` maintains the store registry and executes checkout lifecycle effects. `WorkspaceCoordinatorReducer` owns selection, creation, recovery, cleanup and aggregate quit decisions. Git worktree operations revalidate repository, branch, path and clean-file ownership; removal retains the branch and durable task record.

Shared persistence preserves existing project/thread keys and ordering. Task pins retain compact conversation summaries in shared local preferences, independent of the selected project. The sidebar shows pinned tasks and pinned projects in a global Pinned section, with the current project's expanded chats beneath its project row; opening a task from another project carries its thread ID through project adoption. Successful archive or permanent deletion removes its pin, and successful renames refresh its pinned title. Task context-menu mutations capture the row identity and revalidate workspace ownership and management eligibility before execution. Manual unread markers remain local to the navigation session and clear when the task is opened. Project context menus offer Pin or Unpin, Rename, Reveal in Finder, Archive chats and Remove project in that order. Rename changes only the local display name. Its custom AppKit sheet preselects that name and provides Save, Cancel and Close; Return or keypad Enter commits the field and saves, while Escape cancels. Completion retains the captured project and callback and revalidates the modal scope. Removal persistently hides the project and removes its project pin without deleting its folder, chats, individual task pins or drafts; explicitly reopening the folder restores its sidebar entry. Archive chats lists all unarchived conversations in the target checkout, validates their ownership and active status, then archives them sequentially. It removes individual pins only for confirmed archived chats and reports partial failures. A pending project archive blocks new work and checkout cleanup until completion.

## Presentation

AppKit callbacks dispatch captured `WorkspaceIntentTarget` intents and render narrow read-only presentations. `WorkspaceEligibility` shares capability rules between selectors and reducers, with admission checked again when an intent is reduced. Publication is coalesced while all accepted backend events are processed in order. Transcript preparation runs asynchronously and superseded renders are cancelled without changing AppKit's ownership of focus and scrolling.

`ThreadTitleText` in `Application/State/` owns shared whitespace normalization, the
120-character title limit and the provisional empty-title fallback. Protocol response decoding,
submission transitions and display selectors consume that same policy; protocol JSON validation
remains in `CodexClient/AutomaticTitleResponse`.

Conversation display titles prefer a nonblank thread name, then normalized request text from the preview, then the checkout path, then "New chat". Complete generated attachment envelopes are validated with the shared user-message parser and excluded from display titles; ordinary or incomplete text stays literal. Presentation does not modify stored names, previews or history. Task hover cards limit title and project text to three and two lines respectively, truncate overflow and stay within the visible screen.

Feature placement follows the [feature map](../Sources/CodexGUI/Features/README.md). Terminal invocations remain transcript activity and are excluded from the canonical Sources inventory. Source counts, summary and tab presentation must agree. Both Sources and transcript attachments use `Features/Shared/SourceThumbnailLoader`. The shared actor bounds input decoding, prepares pixels off the main actor and reuses decoded thumbnails. `CodexClient/InlineImageData` handles inline payload identification and bounded decoding; `Application/Services/LocalAttachmentURL` resolves local paths and file URLs. The thumbnail `NSCache` is configured for 64 entries and 16 MiB of estimated pixel/key cost, separate from workspace content residency. File reads and decoded inline payloads are bounded to 32 MiB; Sources request 80-pixel thumbnails and model-response images request up to 800 pixels within a per-message budget. Expanded previews initially decode up to 2048 pixels and request sharper pixels as zoom requires, capped at 8192 pixels on the longest edge. Original dimensions retain image orientation for zoom geometry. Composer and transcript attachment tiles use shared centered aspect-fill drawing: preserve the image proportions, fill the square and clip overflow equally on opposite edges. AppKit views retain generation checks and cancellation on reuse.

Composer attachments, transcript attachments and viewed-image activity use the shared `ExpandedImagePreview` coordinator and `ExpandedImageViewController` in `Features/Shared`. The viewer overlays the parent window content with a native within-window blur beneath a separate dimming layer. The image and header controls remain above these backdrop layers. It fits the full image and offers percentage zoom, Actual Size, pinch magnification and scrolling. Fit centers the complete image within a viewport inset 68 points on each side, below the header and above an 82-point bottom reserve. Fit uses the smaller of the available-width/original-width and available-height/original-height ratios, capped at 100%. Width-limited images share the available width; height-limited images share the available height. Image proportions and centering are preserved. Resizing recalculates Fit, while explicit percentage zoom remains unchanged. Actual Size (100%) maps an original image pixel to one layout point; sharper decoding accounts for the screen backing scale. Close and Escape dismiss the viewer and restore the prior responder when it still belongs to the parent window. Replacing its attachment or activity owner, detaching its originating view or closing the window cancels pending loading and dismisses the overlay. Underlying content siblings are temporarily hidden from assistive technology, with their original accessibility visibility restored on dismissal. Inline payloads remain in memory; previewing them does not create a file. The viewer has no external-open, download or image-editing controls.

Markdown presentation belongs to `Features/Shared/Markdown`, used by transcript messages and Git
rich previews. It owns parsing, native text and decoration rendering, source-preserving selection
copy and accessibility, rich attachments, and plain-text output. Parsed values remain `Sendable`,
so consumers can prepare Markdown off the main actor. AppKit rendering and layout stay on the
main actor.
Shared transcript presentation owns message preparation and containers; Conversation retains
turn-preview adapters and application state retains content residency. Changes owns Git content
loading, cancellation and preview containers. Each consumer
retains its own sizing, scrolling and appearance-refresh lifecycle. Rendering caches and resource
limits stay with the shared renderer; feature content caches stay with their feature.

The main conversation and subagent history compose `TranscriptViewController` from
`Features/Shared/Transcript`. Its presentation carries the captured owner, history and explicit
execution evidence. The child owns row preparation, selection, reading anchors, scrolling,
navigation and their asynchronous cancellation. Conversation retains the composer, submission
and live task controls; Subagents retains history loading, agent metadata and retry controls.
Both consumers route transcript actions through their own callbacks. History marked in progress
does not supply live execution evidence for elapsed timers.

Markdown images in message bodies resolve only local paths, local file URLs and bounded inline image data. Preparation decodes thumbnails off the main actor through `SourceThumbnailLoader`; remote and unavailable images retain readable source text. Consecutive image-only paragraphs form a source-backed native gallery of rounded, bordered cards. Cards retain each image's original aspect ratio, fit within 160 points of height and 425 points of width, and wrap to the next row when they cannot fit beside the preceding card. Clicking a gallery image opens that image in the shared expanded preview, which closes when its text view changes owner or detaches. The gallery's Markdown remains available to selection copy and accessibility help. The thumbnail cache and per-message rich-image budget bound decoded image retention.

Pure reported-patch composition belongs to `Application/Reducers/Review/ConversationNetFileChanges`. `ConversationNetFileChangePreparation` prepares those results off the main actor and retains exact inputs and outputs for reuse within the same transcript context. Its reusable cache defaults to 256 entries and 8 MiB. `TranscriptPreparationCoordinator` publishes prepared text, navigation summaries and net file changes together only for the accepted render generation. Current resident content can produce results larger than the reusable cache budget; those results are available to the current render without entering that cache. Folded completed work defers hidden message preparation until disclosure or navigation reveals it.

New local user rows appear synchronously with literal text while rich preparation runs. This
provisional render retains already displayed entries from the same transcript context and never
carries entries across chats. The accepted prepared generation replaces the provisional content
through the existing row, selection and scrolling update path.

See [conventions](../CONVENTIONS.md) for source ownership and test organization, and [validation](validation.md) for verification commands and acceptance limits.

Git comparison file headers offer rich preview for Markdown, images and PDFs supported by the
native renderer; source and configuration files omit that control. Preview reads the target Git
blob, or the base blob for a deleted file. Unstored working-tree bytes must match the comparison's
blob identity, with an 8 MiB read limit. Comparisons without a complete blob identity leave the
control disabled. The eye button toggles between inline rich content and the retained diff in
that file's section. Markdown measures its height at the current width and uses the comparison's
outer vertical scroll view; images fit the section and PDFs use an embedded native viewer.
Preview loading is cancelled when dismissed or when its section is discarded. Retained Markdown
refreshes under its owning view's appearance when the theme changes.

Git display options are application state shared by review actions, reducers and runtime. Diff
projection and native rendering consume those options from `Application/State/` and remain owned
by Changes.

Code panes in the Git comparison own horizontal scrolling. Vertical wheel gestures over their
text or gutters route to the enclosing comparison viewer in both unified and split layouts,
including when code wrapping is enabled. Shift-wheel input retains native horizontal handling.

Editor preferences and macOS file launching belong to `Application/Services/EditorOpeningService`.
Callers supply a project, path and line; the service preserves project containment checks,
preferred-application persistence and launch fallbacks. Changes retains the adapter that derives
the relevant line from a Git diff. Settings accesses the same preference owner directly.

Sources owns its media preview coordinator within the feature. The coordinator owns request
identity, cancellation and rejection of obsolete results, including interrupted requests that
must restart after hidden inventory updates. The Sources controller owns retained rows, selection,
disclosures and application of accepted preview results to native views.

The Git comparison controller owns repository requests, comparison controls and file navigation.
Its child document controller owns retained diff sections, projection caching, layout preferences,
collapse state, scrolling and inline rich-preview presentation. Document callbacks request runtime
actions through the parent; section identity and owner changes govern reuse and invalidation.

Saved-prompt presentation remains within ProjectContext. Its section controller owns prompt rows
and review/edit dialogs, while the parent retains canonical project context and scoped mutation
receivers. Project changes invalidate deferred edits; draft-owner changes independently invalidate
insertion into a conversation. Extracted presentation must preserve both lifetimes.

## Recorded latest Git turn

`ConversationReportedGitTurn` in `Application/Reducers/Conversation/` retains the known latest editing turn's identity and available timestamps independently of loaded transcript bodies. `ConversationReportedGitTurnProjection` in `Application/Presentation/` resolves that identity against currently resident reported changes. Missing or evicted payload is unavailable; an authoritative completed file-change report containing no changes produces an empty result. Older loaded edits cannot replace a known later editing turn without trusted ordering evidence.

Turn-change badge totals are projected in `Application/Presentation/ConversationTurnChangeSummary`.
`Application/Runtime/Review/ConversationTurnChangeSummaryLoader` owns comparison execution,
cancellation and publication from explicit request and active-turn inputs. Conversation owns the
native badge and its actions. Both inputs participate in loader identity so changing the active
turn refreshes previous-turn presentation even when the reported comparison request is unchanged.

All conversation View changes actions open Last Turn for the selected task: its active turn while running, otherwise its latest recorded editing turn. The bottom running-turn badge and Last Turn viewer calculate counts from completed file-change reports, deduplicated by item identity. While the active turn has no available reports, only the badge may reuse the selected task's latest available editing-turn reports. The badge title always shows only the changed-file count and line counts; fallback details remain in its tooltip and accessibility description. The badge never displays comparison failures: if a comparison fails, it counts the available reported patches directly, independently of the viewer preview limit. With no available reports it displays zero file and line counts. The Last Turn viewer retains its unavailable and error states. Active reports, including an authoritative empty report, replace those badge counts as soon as they arrive. The Last Turn viewer retains active-turn selection while running; opening it from a previous-turn badge does not change that selection. Neither uses a working-tree baseline nor the backend aggregate diff to attribute edits: those comparisons can include another task's changes, including interleaved edits to the same file. Missing or evicted Last Turn reports remain explicitly unavailable, without retaining another turn's viewer snapshot or totals. Empty recorded reports are distinct from missing reports; compatible reversals produce no net changes. Incompatible or over-budget patch sequences fall back to retaining the reported patches, as transcript summaries do. The badge tooltip and viewer describe this fallback as reported edit counts, which may count repeated edits more than once and are not net changes. Fallback patches have no copy-to-apply command because they may not form an applicable combined patch. The 8 MiB comparison preview limit still applies.

Transcript change cards, their file and line totals, and Last Turn comparisons include only reported
paths within the selected checkout when its absolute path is known. Relative paths are resolved
against that checkout; paths outside it, including edits to temporary source copies, are excluded.
Rename reports must keep both paths within the checkout. This filter uses normalized paths without
reading files or treating matching filenames in another checkout as the same file. Raw backend
reports remain unchanged. A checkout located under `/tmp` still includes its own reported edits.

Last Turn covers reported edits only. Arbitrary shell writes and subagent edits not reported under the selected task's turn are excluded and disclosed in the UI. Child-thread identity alone does not prove which parent turn owns an edit; the client does not infer that relationship from a shared directory, filenames or activity timing. Complete coverage requires backend write attribution or isolated task checkouts. Repository comparison scopes such as Uncommitted retain checkout-wide semantics. The recorded turn identity does not retain a separate unbounded patch cache.

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

These byte costs estimate decoded textual payload and retained entry bodies, not total process memory or AppKit attributed strings, images and layout overhead. Visible turns, the reading anchor, the pending jump target and a live execution turn are protected. Protected oversized content may exceed the budget; background neighborhood fetching then pauses. Hover-only bodies are discarded before transcript content. Unprotected full turns and compact previews use least-recently-used eviction.

Viewport publication is debounced and scoped to the presentation owner. Neighbor reads run serially and queued targets follow the current anchor. Foreground navigation supersedes background neighborhood reads; the runner retains at most one local read in each role (navigation, preview, neighborhood). Preview reads do not change transcript entries or reading position. A click promotes an existing preview fetch; incomplete boundary-page previews require a subsequent full-content read before navigation.

Evicted turns retain metadata references. Visible missing ranges receive explicit gap markers and are hydrated as the reader approaches them. Jump resolution excludes gap markers. Existing reading-anchor restoration preserves message identity and pixel offset when entries are removed or inserted. The Latest action targets the latest rail turn, including when its contents were evicted. Manual transcript wheel input supersedes a pending rail navigation or its animation; wheel input on the rail remains independent.

Completion/error responses remain guarded by workspace, connection generation, thread, request identity and command revision. Backend mutations invalidate cached previews for the affected turn. Expiration is scheduled by the runtime; reducer cache time is supplied by timestamped actions.
