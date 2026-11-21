# Swift regression routes and Tauri evidence

Use the pinned Swift revision in the [parity baseline](tauri-parity.md). For each Swift test, take the first matching source path below, relative to `Tests/CodexGUITests`. A row assigns the Tauri acceptance for every case in its source files. For a mixed suite, exercise each distinct assertion under the owning checkpoint within the listed range. Review the original inputs, event ordering, ownership, and storage isolation before marking the corresponding Tauri case complete.

## Swift test routes

| Swift test source selector | Tauri checkpoint and evidence |
| --- | --- |
| `CodexClient/AppServer/AppServerAccountTests.swift` | C105, C122. Portable account fixture checks the selected profile and scoped refresh. |
| `CodexClient/AppServer/AppServerApprovalRoutingTests.swift`, `CodexClient/AppServer/AppServerUnsupportedInteractionTests.swift`, `CodexClient/Protocol/ApprovalDecisionTests.swift` | C31, C47, C50. Protocol fixture exercises exact request IDs, valid choices and interaction settlement. |
| `CodexClient/AppServer/AppServerAutomaticTitleTests.swift`, `CodexClient/Decoding/AutomaticTitleResponseTests.swift` | C93. Portable title response and captured chat tests. |
| `CodexClient/AppServer/AppServerFeedbackTests.swift`, `Application/Reducers/ResultFeedback/*` | C96. Portable fixture checks eligibility, exact turn, logs exclusion and uncertain outcome. |
| `CodexClient/AppServer/AppServerQueueTests.swift`, `Application/Runtime/Conversation/*Queue*Tests.swift`, `Persistence/ComposerQueueStorageTests.swift` | C34–C35, C51–C58. Fixture backend and database verify queue authority, receipts, sequencing, mutation isolation and paused restore. |
| `CodexClient/AppServer/AppServerRemoteAccessTests.swift`, `CodexClient/Diagnostics/RemoteControlDiagnosticsTests.swift`, `Application/Reducers/RemoteAccess/*`, `Features/RemoteAccess/*` | C119–C120. Relay fixture and installed Settings route prove workspace ownership, pairing, revocation and reconnect. Actual relay and device acceptance belongs to C150. |
| `CodexClient/AppServer/AppServerVoiceChatTests.swift`, `Application/Runtime/VoiceChatRuntimeTests.swift`, `Application/Presentation/VoiceChatTranscriptTests.swift`, `Features/Settings/Pages/SettingsVoicePageTests.swift` | C112–C116. Realtime fixture and synthetic media verify chat ownership, settings preview, transcript history and coding handoff. |
| `CodexClient/AppServer/AppServerReadAloudTests.swift`, `Application/Reducers/ReadAloud/*`, `Application/Runtime/ReadAloud*Tests.swift` | C113, C117. Synthetic speech verifies playback controls, failures, retirement and owner reuse. |
| `CodexClient/AppServer/AppServerConfiguredDefaultsTests.swift`, `Application/Reducers/Preferences/*`, `Persistence/ReasoningEffortVisibilityTests.swift` | C83, C105–C106. Fixture separates saved preferences from effective policy, capability and next-turn state. |
| `CodexClient/AppServer/SlashCommandAppServerTests.swift`, `App/SlashCommandPresentationTests.swift`, `Application/Runtime/Conversation/ComposerCommand*Tests.swift` | C85. Installed composer and protocol fixtures verify argument handling, literal text and async command completion. |
| `CodexClient/AppServer/AppServerThreadManagementTests.swift`, `Application/Runtime/Workspace/ProjectArchiveRuntimeTests.swift`, `Features/Settings/ArchivedChats/*` | C88, C90–C91. Verify scoped archive catalog reads, confirmed mutations and preserved partial outcomes. |
| `CodexClient/AppServer/AppServerHistoryLoadingTests.swift`, `CodexClient/AppServer/AppServerPaginationTests.swift`, `CodexClient/Decoding/ConversationHistoryDecoderTests.swift` | C15, C33, C73–C76. Portable pagination and stable identity tests verify full history, summary reads, and representation-specific decoding. |
| `CodexClient/Decoding/InlineImageDataTests.swift` | C79. Malformed and scoped image source fixtures. |
| `CodexClient/Protocol/FileChangeTests.swift`, `Application/Presentation/*Git*Tests.swift`, `Application/Runtime/Conversation/GitTurnBaselineExecutionTests.swift` | C29, C67–C70, C103. Match authoritative reported-change identity and protect the equivalent Send, comparison and reconciliation outcomes. Keep the before-tree capture cases as Swift reference evidence for its retired path. |
| `CodexClient/AppServer/*`, `CodexClient/Protocol/*`, `CodexClient/Transport/*` | C07–C15, C28–C35. Portable process, wire and state fixtures verify connection scope, framing, delivery, timeout and turn lifecycle. |
| `Application/Reducers/Composer/*`, `Application/Services/Composer*Tests.swift`, `Application/State/CodeRangeSelectionTests.swift` | C27, C46, C79–C85. Verify the original composer, exact input construction, attachment lifetimes, selection ranges and scoped commands. |
| `Application/Reducers/Connection/*`, `Application/Reducers/Execution/*`, `Application/Runtime/Conversation/ConcurrentChatRuntimeTests.swift`, `Application/State/ConversationExecutionRegistryTests.swift` | C26, C28–C35, C47, C64–C66. Interleave hidden owners, retired generations, duplicate events and command exit. |
| `Application/Reducers/Conversation/*` | C44, C73–C76, C86–C87, C93–C95. Fixture covers scoped history, forks, prompt revision, titles and related conversation state. |
| `Application/Reducers/Navigation/*`, `Features/Navigation/*` | C44, C87–C91. Verify reducer identity and installed keyboard, chooser, sorting, pinning and archive workflows. |
| `Application/Reducers/Review/*`, `Application/Runtime/Review/*`, `Application/Services/Git/*` | C67–C70, C103–C104. Real temporary Git repositories and fixtures cover selectors, immutable comparison, exact patch and report attribution. |
| `Application/Runtime/Conversation/MessageSearchRuntimeTests.swift`, `App/Windows/MessageSearchWindowRebindingTests.swift` | C92. Scoped indexed pages, viewport-independent jumps and stale search controls. |
| `Application/Runtime/Conversation/RestoredRemoteConversationRuntimeTests.swift` | C35, C64, C119–C120. Resume fixtures reconcile hidden remote-started work and retain original execution ownership. |
| `Application/Runtime/Conversation/TurnReferenceRuntimeTests.swift` | C75, C87. Reopen unloaded turn references with event and residency evidence. |
| `Application/Runtime/Workspace/WorkspaceInteractionResponseRuntimeTests.swift` | C31, C47. Verify response reservation, matching generation, authoritative resolution and independent hidden prompts. |
| `Application/Runtime/Workspace/WorkspacePersistenceSchedulerTests.swift` | C23–C25, C66. Faulted writes, scoped drains and preserved retry records. |
| `Application/Runtime/Workspace/*`, `Application/Runtime/ApplicationStateTests/*`, `Application/Composition/*`, `Application/State/*` | C13, C26–C35, C41–C44, C64–C66, C105. Exercise checkout authority, startup, state publication, owner changes, lifecycle and preference/account composition. |
| `Application/Runtime/WorkspacePublicationCoordinatorTests.swift`, `App/Windows/MainWindowPublicationLifecycleTests.swift`, `App/WorkspaceIntentRoutingTests.swift` | C26, C41–C43, C47. Fixture and installed checks prove reservation before publication, correct receiver and reload ordering. |
| `Application/Runtime/Files/*`, `Application/Services/Files/*`, `Application/Services/EditorOpeningServiceTests.swift` | C59–C60, C97–C102. Scoped path, native revision, invalidation and external opening checks. |
| `Application/Runtime/ProjectFiles/*` | C71–C72. Compare watcher updates with a clean scan under burst, replacement and overflow. |
| `Application/Runtime/ProjectContext/*`, `Features/ProjectContext/*`, `Persistence/ProjectContextStorePersistenceTests.swift` | C39, C84, C121. Verify fixture load, preserved edits, repeat import, retry and installed controls. |
| `Application/Services/ImageAnnotationTests.swift`, `Application/Services/LocalAttachmentURLTests.swift`, `UI/Images/*` | C79–C82, C101–C102. Verify source isolation, byte identity, annotated geometry, export and return focus. |
| `Application/Presentation/SourceActivityResultPresentationTests.swift`, `Features/Sources/*`, `Features/Subagents/*` | C95. Match per-chat inspector selection, child transcript paging and preview appearance. |
| `Application/Presentation/*` | C26–C28, C47, C73–C76. Preserve pending-chat state, transcript identity, question-envelope rendering and workspace switching. |
| `App/Account/*` | C49, C105. Installed fixture verifies sign-in actions and account menu ownership. |
| `App/Diagnostics/UITestUIEvidenceTests.swift` | C37–C38. Swift reference evidence checks capture content and bounds. |
| `App/Diagnostics/StatusPopoverViewTests.swift` | C38, C110. Preserve the AppKit capture as reference-only evidence for its status popover. Verify the Tauri controls under the UI-copy rules. |
| `App/GitReview/*`, `Features/Changes/*` | C68–C70, C103–C104. Verify actual compared content, unified/split Changes, jump, hover, exact exports and editor handoff. |
| `App/Notifications/*`, `Features/Settings/Pages/SettingsNotificationControlsTests.swift` | C111. Verify notification routing and sound selection with installed fixtures. Actual receipt, sound and permissions belong to C150–C151. |
| `App/Tools/*`, `App/WindowLayout/*`, `App/Windows/TaskWorkspace*Tests.swift` | C44, C64–C66, C97, C103, C110. Verify per-chat tools adoption, window and modal ownership, split panes and restoration. |
| `App/Design/*`, `App/Windows/*` | C38, C44, C73–C76, C110. Use AppKit-only layout cases for reference measurements and installed Tauri checks for observable presentation and interaction. |
| `Features/Conversation/Composer/*Queue*Tests.swift` | C57. Installed queue controls verify addressed row, edit state, hover, ordering and explicit Resume. |
| `Features/Conversation/Composer/*` | C46–C47, C79–C85, C110. Verify exact typing, control eligibility, focus, content selection, permissions and menu behavior. |
| `Features/Conversation/Transcript/Rows/*Subagent*Tests.swift` | C95. Installed transcript navigation and correctly scoped source rows. |
| `Features/Conversation/*`, `UI/Transcript/*` | C47, C73–C81, C86–C87, C95. Verify transcript layout, rendered groups, image preparation, row reuse, turn references and actionable response controls. |
| `Features/Files/*`, `UI/FileViewer/*` | C97–C102. Check navigation, file search, document content, viewer controls and unavailable source actions. |
| `Features/PinnedSummary/*` | C94. Verify presentation and lifecycle under changes to the owning conversation. |
| `Features/Settings/Browser/*`, `Features/Settings/Management/*` | C109. Verify forms, scoped site actions, policies and preserving failed drafts. |
| `Features/Settings/Usage/*`, `Features/Usage/*` | C105, C108. Verify missing and zero usage, eligibility, account identity and expired credits. |
| `Features/Settings/Pages/SettingsConfigurationPageTests.swift`, `Features/Settings/SettingsBackendTests.swift` | C105–C107. Verify capability and settings writes, policy, refresh and hidden view retirement. |
| `Features/Settings/*`, `UI/Color/*`, `UI/Typography/*` | C38, C110, C126–C146 and C151. Check appearance, search navigation, typography and resolved colors on installed surfaces. Keep Cocoa-specific styling assertions as Swift reference cases. |
| `UI/Components/Output/*` | C73, C77. Compare rendered output and exact copy text from portable content fixtures. |
| `UI/Components/Search/*` | C89, C92, C98–C99. Verify query, key navigation, panel lifetime and focus return in the installed app. |
| `UI/Components/*` | C38, C44, C47, C110. Use Swift control-specific assertions for reference and verify matching Tauri behavior, geometry and keyboard/focus where applicable. |
| `UI/Markdown/*` | C77–C78. Check offline rendering, bounded media, escaping and exact copy in installed WebViews. |
| `Persistence/ComposerContextStorageTests.swift`, `Persistence/DraftImageStoreTests.swift`, `Persistence/LocalStorage*Tests.swift` | C23–C25, C40, C121. Verify copied current and legacy data, independent draft revisions, sent references, image leases and durable identity. |
| `Workspaces/*` | C61–C66, C124–C125. Reproduce ownership, cleanup, restart and Git effects in copied temporary workspaces. |

## Native QA routes

The [native harness](native-qa.md#xcode-launched-app-workflow) owns the Swift launch procedure. Run the case steps from the [pinned Xcode suite](https://github.com/cagdasyardimci/codex-gui/blob/c0824558b060d90a6486c3aef743877677f0d4f1/Tests/E2E/StreamingStopWorkflowTests.swift) and retain their artifact provenance when reproducing observations.

| Swift scenario | Tauri checkpoint and evidence |
| --- | --- |
| `testSendStreamingMessageAndStop` and its compact variant | C44, C47, C50, C110. Installed fixture covers the picker, Send, interrupt, retained content and native compact layout. |
| `testComponentsInLightAppearance` and `testComponentsInDarkAppearance` | C38, C89, C97–C103, C110 and C126–C146. Pair captures for the conversation, keyboard chooser and presented panels against the same fixture and window size. Verify the focus-return assertions in the installed app. |
| `streaming` | C16, C43, C47, C50. Compare exact ordered deltas and stop completion on mounted views. |
| `concurrent-streaming` | C26, C31–C35, C43, C47, C50. Verify captured owner and independent hidden streams with a separate checkout and backend trace. |
| `questions` | C31, C47, C50, C118. Exercise question identity, ordered answers, hidden prompts and captured dictation. |
| `stalled-stream` | C11, C32–C33, C47, C50. Match bounded stop and recovery under stalled output. |
| `backend-error` | C08–C12, C29–C33, C47, C50. Match process and stream failures, recoverable drafts and receipt classification. |

## Evidence records

Keep one record per expected assertion or observed scenario outcome. Include the Swift revision and source path or scenario ID, the Tauri commit and acceptance checkpoint, evidence kind, fixture and trace IDs, exact executable and package versions, OS and WebView, outcome, and local artifact paths. Record the expected and observed result and identify failed steps. Use separate evidence kinds for portable fixtures, installed interaction, paired visual acceptance, Swift reference only, and live service acceptance.

Record published state revisions and backend messages at stable checkpoints. Preserve request correlation and event ordering in sanitized traces. Use isolated fixture preferences, support roots, checkouts and backend state for every run. Store paired visual captures with the same content, appearance, viewport, display scale and control state, and record available rendered geometry, fonts and colors. Follow the [validation guide](validation.md#native-and-live-acceptance) when interpreting outcomes.
