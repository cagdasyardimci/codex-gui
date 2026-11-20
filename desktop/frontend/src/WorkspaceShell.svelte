<script lang="ts">
  import { onMount, tick } from 'svelte';
  import { invoke } from '@tauri-apps/api/core';
  import type { ChatRequest, ComposerContextTarget, ComposerTokenRange, ConfirmDeleteChat, DeleteChatSource, DraftAttachmentScope, DraftEdit, FeedbackRating, InteractionAnswer, NavigationIntent, OpenFileSearchHit, ProjectContextChange, QueueCommand, RestoreArchive, ReviewDelivery, ReviewTarget, SendRequest, SentPromptEdit, SidebarChange, SlashCommand, TranscriptItem, TranscriptRowRequest, WorkspaceId, WorkspaceSnapshot, WorkspaceUpdate } from './generated/workspace';
  import InteractionCard from './InteractionCard.svelte';
  import QuitDialog from './QuitDialog.svelte';
  import WorkspaceChanges from './WorkspaceChanges.svelte';
  import QueuePanel from './QueuePanel.svelte';
  import ComposerAttachments from './ComposerAttachments.svelte';
  import ComposerContextPicker from './ComposerContextPicker.svelte';
  import ComposerSettingsControls from './ComposerSettingsControls.svelte';
  import ProjectContextPanel from './ProjectContextPanel.svelte';
  import SlashCommandPanel from './SlashCommandPanel.svelte';
  import ReviewPanel from './ReviewPanel.svelte';
  import SettingsWindow from './SettingsWindow.svelte';
  import type { AppearanceView } from './generated/workspace';
  import { applyDesktopAppearance, observeDesktop } from './desktopAppearance';
  import { verifyAppearance } from './appearanceProbe';
  import VoiceControls from './VoiceControls.svelte';
  import { DesktopVoice } from './desktopVoice';
  import { SpeechPlayback } from './speechPlayback';
  import { verifyReadAloud } from './readAloudProbe';
  import { verifyVoiceHistory } from './voiceHistoryProbe';
  import { verifyVoice, verifyVoiceHandoff, verifyVoiceNoFallback, verifyVoiceReconnect } from './voiceProbe';
  import type { VoiceCallView, VoiceReconnect } from './generated/workspace';
  import { verifyNotifications } from './notificationProbe';
  import { verifySettings } from './settingsProbe';
  import SentPromptDialog from './SentPromptDialog.svelte';
  import WorkspaceSidebar from './WorkspaceSidebar.svelte';
  import CommandPalette from './CommandPalette.svelte';
  import ArchivedChats from './ArchivedChats.svelte';
  import DeleteChatDialog from './DeleteChatDialog.svelte';
  import MessageSearch from './MessageSearch.svelte';
  import PinnedSummary, { type SummarySource } from './PinnedSummary.svelte';
  import ConversationInspector, { type InspectorSelection, type InspectorTab } from './ConversationInspector.svelte';
  import WorkspaceFiles from './WorkspaceFiles.svelte';
  import FileSearch from './FileSearch.svelte';
  import { FileEdits, type FileViewPositions } from './fileTools';
  import { MessageSearchIndex, type SearchHit } from './messageSearchIndex';
  import { paletteEntries, type PaletteEntry, type PaletteMode } from './commandPalette';
  import TranscriptRow from './TranscriptRow.svelte';
  import TurnRail from './TurnRail.svelte';
  import { createTranscriptViewport } from './transcriptViewport.svelte';
  import { addComposerContext, copyTranscriptRow, executeSlashCommand, loadTranscriptAttachment, navigateWorkspace, observeWorkspace, openMessageSearch, openSentPrompt, pasteComposerImage, pickComposerAttachments, pickWorkspace, prepareChatDeletion, readMessageSearchPage, revealSidebarProject, searchProjectPaths } from './projectIpc';
  import { verifyHistory } from './historyProbe';
  import { verifyAccount } from './accountProbe';
  import { verifyWindowsSetup } from './windowsSetupProbe';
  import { verifyTurn } from './turnProbe';
  import { verifyQueue } from './queueProbe';
  import { verifyDiff } from './diffProbe';
  import { verifyQuit } from './quitProbe';
  import { verifyComposerAttachments } from './composerAttachmentProbe';
  import { verifyImageAnnotations } from './imageAnnotationProbe';
  import { verifyComposerContext } from './composerContextProbe';
  import { verifyComposerSettings } from './composerSettingsProbe';
  import { verifyProjectContext } from './projectContextProbe';
  import { verifySlashCommands } from './slashCommandProbe';
  import { verifyPromptRevision } from './promptRevisionProbe';
  import { verifyConversationFork } from './conversationForkProbe';
  import { verifySidebar } from './sidebarProbe';
  import { verifyCommandPalette } from './commandPaletteProbe';
  import { verifyArchive } from './archiveProbe';
  import { verifyChatDeletion } from './chatDeletionProbe';
  import { verifyMessageSearch } from './messageSearchProbe';
  import { verifyAutomaticTitles } from './automaticTitlesProbe';
  import { verifyPinnedSummary } from './pinnedSummaryProbe';
  import { verifyInspector } from './inspectorProbe';
  import { verifyFileTools } from './fileToolsProbe';
  import { verifyFeedback } from './feedbackProbe';
  import 'katex/dist/katex.min.css';
  import './workspace.css';

  let { verify }: { verify?: 'initial' | 'restore' | 'attachments' | 'annotations' | 'composerContext' | 'composerSettings' | 'projectContext' | 'slashCommands' | 'promptRevision' | 'conversationFork' | 'sidebar' | 'sidebarRestore' | 'commandPalette' | 'archive' | 'chatDeletion' | 'messageSearch' | 'automaticTitles' | 'pinnedSummary' | 'inspector' | 'feedback' | 'fileTools' | 'account' | 'settings' | 'appearance' | 'appearanceRestore' | 'notifications' | 'voice' | 'voiceReconnect' | 'voiceNoFallback' | 'voiceHandoff' | 'voiceHistory' | 'voiceHistoryRestore' | 'readAloud' | 'windowsSetup' | 'turn' | 'activeTurn' | 'queue' | 'diff' | 'quit' } = $props();
  let snapshot = $state<WorkspaceSnapshot | null>(null);
  let editor = $state<HTMLTextAreaElement>();
  let transcript = $state<HTMLDivElement>();
  const viewport = createTranscriptViewport();
  const attachTranscript = viewport.attach;
  const measureTranscriptRow = viewport.measure;
  let restoreTabSelection: (() => void) | undefined;
  let upwardHistory: { ticket: string; before: number; until: number } | undefined;
  let requestingHistory: string | undefined;
  let shownJump: string | undefined;
  let canceledJump: string | undefined;
  let draftId: string | undefined;
  let text = $state('');
  let composing = false;
  let actionPending = $state(false);
  let admittingDraft = $state(false);
  let showingChanges = $state(false);
  let settingsOpen = $state(false);
  let call = $state.raw<VoiceCallView | null>(null);
  let reconnect = $state.raw<VoiceReconnect | null>(null);
  const voice = new DesktopVoice((next) => {
    call = next.call;
    reconnect = next.reconnect;
  }, () => verify === 'voice' || verify === 'voiceReconnect' || verify === 'voiceNoFallback' || verify === 'voiceHandoff');
  let appearance = $state.raw<AppearanceView>();
  let settingsButton: HTMLButtonElement;
  let preferredComparison = $state<'uncommitted' | 'lastTurn'>('uncommitted');
  let showingProjectContext = $state(false);
  let projectContextButton = $state<HTMLButtonElement>();
  let confirmingQuit = $state(false);
  let quietQuitTicket: string | undefined;
  let pending: DraftEdit | null = null;
  let saving: Promise<void> | null = null;
  let contextPicker = $state<{ keyboard(event: KeyboardEvent): boolean }>();
  let contextMenu = $state.raw<{
    scope: DraftAttachmentScope; source: string; query: string; selection: [number, number]; token: ComposerTokenRange | null;
    command?: 'skills' | 'mention';
  }>();
  let commandPanel = $state.raw<{ command: SlashCommand; draft: SendRequest; fullAccess: boolean; inline: boolean }>();
  let slashToken = $state.raw<{ start: number; end: number; prefix: string }>();
  let slashIndex = $state(0);
  let promptEdit = $state.raw<{ row: TranscriptRowRequest; view: SentPromptEdit }>();
  type FocusScope = {
    workspaceId: string | null;
    chatId: string | null;
    draftId: string | null;
    focused: HTMLElement | null;
    selection?: [number, number];
  };
  type PaletteScope = FocusScope & { mode: PaletteMode; entries: PaletteEntry[]; revision: string | null };
  let palette = $state.raw<PaletteScope>();
  let fileSearch = $state.raw<FocusScope & { scope: DraftAttachmentScope }>();
  let archive = $state.raw<{ workspaceId: WorkspaceId | null; control: HTMLElement | null }>();
  type DeletePresentation = {
    request: ConfirmDeleteChat;
    workspaceId: WorkspaceId | null;
    control: HTMLElement | null;
    complete: (confirmed: boolean) => void;
  };
  let deletion = $state.raw<DeletePresentation>();
  let finishingDeletion = $state(false);
  const searchIndex = new MessageSearchIndex();
  let searchRevision = $state(0);
  let search = $state.raw<{ workspaceId: WorkspaceId; session: string; control: HTMLElement | null }>();
  let hiddenSummaries = $state.raw(new Set<string>());
  let checkoutRevision = $state(0);
  let inspectorViews = $state.raw(new Map<string, { opened: boolean; selection: InspectorSelection }>());
  let filePane = $state<ReturnType<typeof WorkspaceFiles>>();
  let filesOpened = $state(false);
  const fileEdits = new FileEdits();
  const filePositions: FileViewPositions = { tabs: new Map(), folders: new Map(), modes: new Map(), pdfPages: new Map() };
  const workspace = $derived(snapshot?.workspace);
  const navigation = $derived(snapshot?.navigation);
  const sidebar = $derived(navigation?.sidebar);
  const projectTitle = $derived(sidebar?.projects.find((project) => project.id === sidebar?.activeProject)?.title);
  const workspaceId = $derived(workspace?.workspaceId);
  const selectedChat = $derived(navigation?.selectedChat);
  let speechAvailable = $state(false);
  let reading = $state.raw<{ scope: string; row: TranscriptRowRequest; player: SpeechPlayback }>();
  const speechScope = $derived(workspaceId && selectedChat && !navigation?.quit && !settingsOpen
    ? JSON.stringify([workspaceId, selectedChat, navigation?.account.identity, navigation?.account.permitsTurns]) : undefined);
  $effect(() => {
    const scope = speechScope;
    speechAvailable = false;
    if (!scope || !workspaceId) return;
    let active = true;
    void invoke<boolean>('can_read_aloud', { workspaceId }).then((available) => {
      if (active) speechAvailable = available;
    }).catch(() => {});
    return () => { active = false; };
  });

  $effect(() => {
    const current = reading;
    if (current && (current.scope !== speechScope || current.row.generation !== transcriptGeneration)) current.player.stop();
  });
  const reconnectHere = $derived(reconnect && sidebar?.activeProject === reconnect.projectId &&
    selectedChat === reconnect.chatId ? reconnect.id : null);
  const voiceInline = $derived(!!call && sidebar?.activeProject === call.projectId && selectedChat === call.chatId);
  const summaryScope = $derived(workspaceId && selectedChat ? { workspaceId, chatId: selectedChat } : undefined);
  const summaryKey = $derived(sidebar?.activeProject && selectedChat
    ? JSON.stringify([sidebar.activeProject, selectedChat]) : undefined);
  const summaryVisible = $derived(!!summaryKey && !hiddenSummaries.has(summaryKey));
  const inspector = $derived(summaryKey ? inspectorViews.get(summaryKey) : undefined);
  const transcriptGeneration = $derived(snapshot?.transcript.generation);
  const displayedDraft = $derived(navigation?.draft?.id);
  const attachmentScope = $derived(workspaceId && displayedDraft
    ? { workspaceId, chatId: selectedChat ?? null, draftId: displayedDraft } : undefined);
  const draftAttachments = $derived(navigation?.draft?.attachments ?? []);
  const finishedTurns = $derived(new Set(navigation?.turnRail?.turns.filter((turn) => turn.finished).map((turn) => turn.id)));
  const feedbackRows = $derived.by(() => {
    const rows = new Set<string>();
    const feedback = navigation?.feedback;
    if (!feedback?.available || quit) return rows;
    const eligible = new Set(finishedTurns);
    for (const turn of feedback.blockedTurns) eligible.delete(turn);
    const items = snapshot?.transcript.items ?? [];
    for (let at = items.length - 1; at >= 0; at--) {
      const row = items[at]!;
      if (!row.spoken && row.role === 'assistant' && row.completed && row.text.trim() && eligible.delete(row.turnId)) rows.add(row.itemId);
    }
    return rows;
  });
  const responseBookmarks = $derived(new Set(navigation?.bookmarkedResponses));
  const slashMatches = $derived(slashToken ? (navigation?.slashCommands.available ?? [])
    .filter((command) => command.startsWith(slashToken!.prefix)) : []);
  const mayExecuteSlash = $derived(!navigation?.literalForkRevision && /^[ \t]*\/[^/\s]/u.test(text) &&
    !!navigation?.slashCommands.available.length);
  const editablePrompts = $derived.by(() => {
    const result = new Set<string>();
    if (!navigation?.canEditSentPrompt) return result;
    const finished = new Set(finishedTurns);
    for (const row of snapshot?.transcript.items ?? []) {
      if (row.role === 'user' && finished.delete(row.turnId) && row.editablePrompt) result.add(row.itemId);
    }
    return result;
  });
  const rowRequests = new WeakMap<TranscriptItem, TranscriptRowRequest>();
  const summarySources = new WeakMap<TranscriptRowRequest, SummarySource[]>();
  const stopTarget = $derived(navigation?.actions.stop);
  const quit = $derived(navigation?.quit);
  const queue = $derived(navigation?.queue);
  const resumeCommand = $derived(queue?.resume ? { resume: queue.resume } :
    queue?.resumeSaved ? { resumeSaved: queue.resumeSaved } : null);

  function rowRequest(item: TranscriptItem) {
    if (!workspaceId || !selectedChat || transcriptGeneration === undefined) return;
    const prior = rowRequests.get(item);
    if (prior?.workspaceId === workspaceId && prior.chatId === selectedChat && prior.generation === transcriptGeneration &&
        prior.revision === item.revision) return prior;
    const request = { workspaceId, chatId: selectedChat,
      itemId: item.itemId, generation: transcriptGeneration, revision: item.revision };
    rowRequests.set(item, request);
    return request;
  }

  function recentSources(limit = 3) {
    const result: SummarySource[] = [];
    const items = snapshot?.transcript.items ?? [];
    for (let at = items.length - 1; at >= 0 && result.length < limit; at--) {
      const item = items[at]!;
      if (!item.attachments.length) continue;
      const row = rowRequest(item);
      if (!row) continue;
      let sources = summarySources.get(row);
      if (!sources) {
        sources = item.attachments.map((attachment) => {
          const media = { row, attachmentId: attachment.id };
          return {
            id: JSON.stringify([row.itemId, attachment.id]), label: attachment.label, media,
            load: attachment.image ? () => loadTranscriptAttachment(media) : undefined,
          };
        });
        summarySources.set(row, sources);
      }
      result.push(...sources.slice(0, limit - result.length));
    }
    return result;
  }

  function toggleSummary() {
    if (!summaryKey) return;
    const hidden = new Set(hiddenSummaries);
    if (!hidden.delete(summaryKey)) hidden.add(summaryKey);
    hiddenSummaries = hidden;
  }

  function openSummaryChanges(scope: ChatRequest) {
    if (scope.workspaceId === workspaceId && scope.chatId === selectedChat && !quit) {
      preferredComparison = 'lastTurn';
      showingChanges = true;
    }
  }

  function updateInspector(scope: ChatRequest, selection: InspectorSelection, opened = true) {
    if (!summaryKey || scope.workspaceId !== workspaceId || scope.chatId !== selectedChat || quit) return;
    inspectorViews = new Map(inspectorViews).set(summaryKey, { opened, selection });
  }

  function openInspector(scope: ChatRequest, tab: InspectorTab, source?: string) {
    const selection: InspectorSelection = { ...inspector?.selection, tab };
    if (source) selection.source = source;
    updateInspector(scope, selection);
  }

  function copyResponse(item: TranscriptItem) {
    const request = rowRequest(item);
    if (request) return copyTranscriptRow(request);
  }

  function readResponse(item: TranscriptItem) {
    const row = rowRequest(item);
    if (!row || !speechAvailable || !speechScope) return;
    const previous = reading;
    previous?.player.stop();
    if (previous?.row.itemId === row.itemId && previous.row.generation === row.generation) return;
    const player = new SpeechPlayback(verify === 'readAloud', () => {
      if (reading?.player === player) reading = undefined;
    });
    reading = { scope: speechScope, row, player };
    player.start((id, events) => invoke('read_aloud', { row, id, events }));
  }

  function sendFeedback(row: TranscriptRowRequest, rating: FeedbackRating) {
    if (row.workspaceId !== workspaceId || row.chatId !== selectedChat || row.generation !== transcriptGeneration) return;
    if (quit) return;
    void navigateWorkspace({ submitFeedback: { row, rating } }).catch((error) => {
      if (error !== 'staleSelection' && error !== 'retiredWorkspace') console.error(error);
    });
  }

  function branchResponse(item: TranscriptItem) {
    const request = rowRequest(item);
    if (request) void act(() => navigateWorkspace({ branchResponse: request }));
  }

  function setResponseBookmark(item: TranscriptItem, bookmarked: boolean) {
    const row = rowRequest(item);
    if (row) void act(() => navigateWorkspace({ setResponseBookmark: { row, bookmarked } }));
  }

  function forkChat() {
    const draft = sendRequest();
    if (!draft?.chatId) return;
    if (navigation?.recoverFork) commandPanel = { command: 'fork', draft, fullAccess: false, inline: false };
    else void act(() => navigateWorkspace({ forkChat: { workspaceId: draft.workspaceId, chatId: draft.chatId! } }));
  }

  function editSentPrompt(item: TranscriptItem) {
    const row = rowRequest(item);
    if (!row) return;
    void act(async () => {
      const view = await openSentPrompt(row);
      if (workspaceId === row.workspaceId && selectedChat === row.chatId &&
          transcriptGeneration === row.generation) promptEdit = { row, view };
    });
  }

  function reviseSentPrompt(text: string) {
    const captured = promptEdit;
    if (!captured) return;
    void act(async () => {
      await navigateWorkspace({ reviseSentPrompt: { ticket: captured.view.ticket, text } });
      if (promptEdit === captured) promptEdit = undefined;
    });
  }

  function cancelSentPromptEdit() {
    const captured = promptEdit;
    promptEdit = undefined;
    if (captured) void navigateWorkspace({ cancelSentPromptEdit: captured.view.ticket }).catch(() => {});
  }

  function retainSelectionForTab() {
    restoreTabSelection = undefined;
    const selection = window.getSelection();
    if (!selection || selection.isCollapsed || !transcript) return;
    const { anchorNode, anchorOffset, focusNode, focusOffset } = selection;
    if (!anchorNode || !focusNode || !transcript.contains(anchorNode) || !transcript.contains(focusNode)) return;
    const generation = snapshot?.transcript.generation;
    const restore = () => {
      if (snapshot?.transcript.generation === generation && transcript?.contains(anchorNode) &&
          transcript.contains(focusNode) && selection.isCollapsed) {
        selection.setBaseAndExtent(anchorNode, anchorOffset, focusNode, focusOffset);
      }
    };
    restoreTabSelection = restore;
    setTimeout(() => {
      if (restoreTabSelection === restore) restoreTabSelection = undefined;
    }, 0);
  }

  function focusResponseAction() {
    const restore = restoreTabSelection;
    restoreTabSelection = undefined;
    if (restore) requestAnimationFrame(restore);
  }

  function requestOlderHistory() {
    upwardHistory = undefined;
    const older = navigation?.olderHistory;
    const chatId = navigation?.selectedChat;
    if (!workspace || !chatId || !older || older.pending || requestingHistory === older.ticket) return;
    const ticket = older.ticket;
    requestingHistory = ticket;
    void navigateWorkspace({ loadOlderHistory: { workspaceId: workspace.workspaceId, chatId, ticket } })
      .catch((error) => {
        if (error !== 'staleSelection' && error !== 'retiredWorkspace') console.error(error);
      }).finally(() => {
        if (requestingHistory === ticket) requestingHistory = undefined;
      });
  }

  function beginUpwardScroll() {
    recordTranscriptInput();
    const older = navigation?.olderHistory;
    if (!older || older.pending || !transcript) return;
    const before = transcript.scrollTop;
    if (before <= 1) requestOlderHistory();
    else upwardHistory = { ticket: older.ticket, before, until: performance.now() + 500 };
  }

  function recordTranscriptInput() {
    viewport.noteInput();
    const rail = navigation?.turnRail;
    const chatId = navigation?.selectedChat;
    const pending = rail?.pendingJump;
    if (!workspace || !rail || !chatId || !pending || canceledJump === pending.ticket) return;
    canceledJump = pending.ticket;
    void navigateWorkspace({ cancelTurnJump: { workspaceId: workspace.workspaceId, chatId, railId: rail.id,
      ticket: pending.ticket } }).catch((error) => {
      if (error !== 'staleSelection' && error !== 'retiredWorkspace') console.error(error);
    });
  }

  function transcriptWheel(event: WheelEvent) {
    if (event.ctrlKey || event.deltaY === 0) return;
    if (event.deltaY < 0) beginUpwardScroll();
    else {
      recordTranscriptInput();
      upwardHistory = undefined;
    }
  }

  function transcriptKey(event: KeyboardEvent) {
    if (event.defaultPrevented || event.isComposing || event.shiftKey || event.altKey) return;
    if (['ArrowUp', 'PageUp', 'Home'].includes(event.key)) beginUpwardScroll();
    else if (['ArrowDown', 'PageDown', 'End', ' '].includes(event.key)) {
      recordTranscriptInput();
      upwardHistory = undefined;
    }
  }

  function transcriptScroll() {
    viewport.scrolled();
    if (!transcript || !upwardHistory) return;
    const { ticket, before, until } = upwardHistory;
    if (ticket !== navigation?.olderHistory?.ticket || performance.now() > until || transcript.scrollTop >= before) {
      upwardHistory = undefined;
    } else if (transcript.scrollTop <= 1) {
      requestOlderHistory();
    }
  }

  function revealTurnJump(current: WorkspaceSnapshot) {
    const jump = current.navigation.turnRail?.jump;
    if (!jump || shownJump === jump.ticket || canceledJump === jump.ticket) return;
    shownJump = jump.ticket;
    upwardHistory = undefined;
    viewport.jump(jump.turnId, jump.itemId);
  }

  function receive(current: WorkspaceSnapshot, change?: WorkspaceUpdate) {
    const previous = snapshot?.navigation.draft;
    searchIndex.observe(current, change);
    searchRevision = searchIndex.revision;
    if (search && (search.workspaceId !== current.workspace?.workspaceId || current.navigation.quit)) closeSearch(false);
    if (contextMenu && (contextMenu.scope.draftId !== current.navigation.draft?.id ||
        contextMenu.scope.workspaceId !== current.workspace?.workspaceId || current.navigation.queue?.editing || current.navigation.quit)) {
      contextMenu = undefined;
    }
    if (commandPanel && (commandPanel.draft.draftId !== current.navigation.draft?.id ||
        commandPanel.draft.workspaceId !== current.workspace?.workspaceId || current.navigation.quit)) commandPanel = undefined;
    if (promptEdit && (promptEdit.row.workspaceId !== current.workspace?.workspaceId ||
        promptEdit.row.chatId !== current.navigation.selectedChat ||
        promptEdit.row.generation !== current.transcript.generation || current.navigation.quit)) cancelSentPromptEdit();
    if (palette && (!matchesFocusScope(palette, current) || current.navigation.quit)) closePalette(false);
    if (fileSearch && (!matchesFocusScope(fileSearch, current) || current.navigation.quit)) closeFileSearch(false);
    if (archive && (archive.workspaceId !== (current.workspace?.workspaceId ?? null) || current.navigation.quit)) archive = undefined;
    if (deletion && !finishingDeletion &&
        (deletion.workspaceId !== (current.workspace?.workspaceId ?? null) || current.navigation.quit)) {
      const retired = deletion;
      settleDeletion(retired, false, false);
      void navigateWorkspace({ cancelChatDeletion: retired.request.ticket }).catch(() => {});
    }
    viewport.receive(current);
    if (snapshot?.transcript.generation !== current.transcript.generation) upwardHistory = undefined;
    if (snapshot?.workspace?.workspaceId !== current.workspace?.workspaceId) {
      showingChanges = false;
      showingProjectContext = false;
    }
    if (snapshot?.workspace?.workspaceId !== current.workspace?.workspaceId || previous?.id !== current.navigation.draft?.id) {
      filesOpened = false;
    }
    snapshot = current;
    revealTurnJump(current);
    if (draftId !== current.navigation.draft?.id) {
      slashToken = undefined;
      draftId = current.navigation.draft?.id;
      text = current.navigation.draft?.text ?? '';
      composing = false;
    } else if (!composing && !pending && previous?.text !== current.navigation.draft?.text &&
               text === previous?.text) {
      text = current.navigation.draft?.text ?? '';
    }
    const request = current.navigation.quit;
    if (request && !request.confirm && !request.draining && request.ticket !== quietQuitTicket) {
      quietQuitTicket = request.ticket;
      void confirmQuit(request.ticket);
    }
  }

  async function savePending() {
    while (pending) {
      const edit = pending;
      pending = null;
      try {
        await navigateWorkspace({ editDraft: edit });
      } catch (error) {
        pending ??= edit;
        throw error;
      }
    }
  }

  function flushEdits() {
    if (!saving && pending) {
      saving = savePending().finally(() => { saving = null; });
    }
    return saving;
  }

  function matchesFocusScope(scope: FocusScope, current: WorkspaceSnapshot | null) {
    return scope.workspaceId === (current?.workspace?.workspaceId ?? null) &&
      scope.chatId === (current?.navigation.selectedChat ?? null) &&
      scope.draftId === (current?.navigation.draft?.id ?? null);
  }

  function openPalette(mode: PaletteMode) {
    if (!snapshot || palette || archive || deletion || search || fileSearch || actionPending || composing || quit || promptEdit || commandPanel) return;
    if (mode === 'files' && !attachmentScope) return;
    palette = { ...captureFocus(snapshot), mode, entries: paletteEntries(mode, snapshot.navigation),
      revision: snapshot.navigation.sidebar.revision };
  }

  function captureFocus(current: WorkspaceSnapshot): FocusScope {
    const focused = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const selection: [number, number] | undefined = (focused instanceof HTMLTextAreaElement || focused instanceof HTMLInputElement) &&
      focused.selectionStart !== null && focused.selectionEnd !== null
      ? [focused.selectionStart, focused.selectionEnd] : undefined;
    return {
      workspaceId: current.workspace?.workspaceId ?? null, chatId: current.navigation.selectedChat,
      draftId: current.navigation.draft?.id ?? null, focused, selection,
    };
  }

  async function restoreFocus(scope: FocusScope, selected = false) {
    await tick();
    if (selected || !scope.focused?.isConnected || !matchesFocusScope(scope, snapshot)) {
      editor?.focus({ preventScroll: true });
      return;
    }
    scope.focused.focus({ preventScroll: true });
    if (scope.selection && (scope.focused instanceof HTMLInputElement || scope.focused instanceof HTMLTextAreaElement)) {
      scope.focused.setSelectionRange(...scope.selection);
    }
  }

  function closePalette(restore = true) {
    const captured = palette;
    palette = undefined;
    if (captured && restore) void restoreFocus(captured);
  }

  function showFileSearch() {
    if (!snapshot || !attachmentScope || fileSearch || palette || archive || deletion || search || quit || promptEdit || commandPanel || actionPending || composing) return;
    fileSearch = { ...captureFocus(snapshot), scope: attachmentScope };
  }

  function closeFileSearch(restore = true) {
    const captured = fileSearch;
    fileSearch = undefined;
    if (captured && restore) void restoreFocus(captured);
  }

  async function chooseFileSearch(hit: OpenFileSearchHit) {
    const captured = fileSearch;
    if (!captured || !matchesFocusScope(captured, snapshot) || actionPending || quit) return;
    actionPending = true;
    try {
      if (await filePane?.openMatch(hit) && fileSearch === captured) closeFileSearch(false);
    } finally {
      actionPending = false;
    }
  }

  async function lookupPaletteFiles(query: string): Promise<PaletteEntry[]> {
    const captured = palette;
    if (captured?.mode !== 'files' || !captured.workspaceId) return [];
    const matches = await searchProjectPaths({ workspaceId: captured.workspaceId, query });
    if (palette !== captured || !matchesFocusScope(captured, snapshot)) return [];
    return matches.map(({ id, displayPath }) => {
      const separator = displayPath.lastIndexOf('/');
      return { id: JSON.stringify(id), title: displayPath.slice(separator + 1),
        detail: separator < 0 ? undefined : displayPath.slice(0, separator), destination: { file: id } };
    });
  }

  async function choosePalette(entry: PaletteEntry) {
    const captured = palette;
    if (!captured || !matchesFocusScope(captured, snapshot) || actionPending || composing || quit) return;
    actionPending = true;
    try {
      await flushEdits();
      if (!matchesFocusScope(captured, snapshot)) throw 'staleSelection';
      const target = entry.destination;
      if ('file' in target) {
        if (await filePane?.openPath(target.file, true)) closePalette();
        return;
      }
      if ('project' in target || 'chat' in target) {
        if (!captured.revision) throw 'staleSelection';
        const change = 'project' in target ? { openProject: target.project } : { openChat: target.chat };
        await navigateWorkspace({ sidebar: { revision: captured.revision, change } });
        closePalette(false);
        await restoreFocus(captured, true);
        return;
      }
      if (target.action === 'browse') {
        closePalette(false);
        const picked = await pickWorkspace();
        await restoreFocus(captured, picked !== null);
        return;
      }
      if (target.action === 'archivedChats') {
        closePalette(false);
        openArchive(captured.focused);
        return;
      }
      const workspaceId = captured.workspaceId;
      if (!workspaceId) throw 'staleSelection';
      if (target.action === 'quickOpen') {
        if (attachmentScope) palette = { ...captured, mode: 'files', entries: [] };
        return;
      }
      if (target.action === 'fileSearch') {
        if (attachmentScope) {
          closePalette(false);
          fileSearch = { ...captured, scope: attachmentScope };
        }
        return;
      }
      if (target.action === 'messageSearch') {
        closePalette(false);
        await displayMessageSearch(workspaceId, captured.focused);
        return;
      }
      if (target.action === 'changes') {
        preferredComparison = 'uncommitted';
        showingChanges = true;
      }
      else if (target.action === 'projectContext') showingProjectContext = true;
      else {
        const intent = { [target.action]: { workspaceId } } as NavigationIntent;
        await navigateWorkspace(intent);
        if ((target.action === 'refresh' || target.action === 'reconnect') && matchesFocusScope(captured, snapshot)) {
          checkoutRevision += 1;
        }
      }
      closePalette(false);
      await restoreFocus(captured, target.action === 'newChat');
    } catch (error) {
      if (error !== 'staleSelection' && error !== 'retiredWorkspace') console.error(error);
      if (palette === captured && snapshot && matchesFocusScope(captured, snapshot)) {
        palette = { ...captured, entries: paletteEntries(captured.mode, snapshot.navigation),
          revision: snapshot.navigation.sidebar.revision };
      }
    } finally {
      actionPending = false;
    }
  }

  async function displayMessageSearch(workspaceId: WorkspaceId, control: HTMLElement | null) {
    const session = await openMessageSearch(workspaceId);
    if (snapshot?.workspace?.workspaceId !== workspaceId || quit) {
      await navigateWorkspace({ closeMessageSearch: session }).catch(() => {});
      return;
    }
    search = { workspaceId, session, control };
  }

  function showMessageSearch() {
    const workspaceId = snapshot?.workspace?.workspaceId;
    if (!workspaceId || search || fileSearch || palette || archive || deletion || promptEdit || commandPanel) return;
    const control = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    void act(() => displayMessageSearch(workspaceId, control));
  }

  function closeSearch(restoreFocus = true) {
    const capture = search;
    if (!capture) return;
    search = undefined;
    void navigateWorkspace({ closeMessageSearch: capture.session }).catch(() => {});
    if (restoreFocus) void tick().then(() => {
      if (capture.control?.isConnected) capture.control.focus({ preventScroll: true });
      else editor?.focus({ preventScroll: true });
    });
  }

  async function loadSearchPage(chatId: string, restart: boolean) {
    const capture = search;
    if (!capture) throw 'staleSelection';
    const page = await readMessageSearchPage({ session: capture.session, chatId, restart });
    if (search !== capture) throw 'staleSelection';
    searchIndex.recordPage(chatId, page);
    searchRevision = searchIndex.revision;
    return page;
  }

  function chooseSearchHit(hit: SearchHit) {
    const capture = search;
    if (!capture || !searchIndex.contains(hit)) return;
    void act(async () => {
      if (search !== capture || !searchIndex.contains(hit)) throw 'staleSelection';
      try {
        await navigateWorkspace({ openMessageSearchHit: {
          workspaceId: capture.workspaceId, session: capture.session,
          chatId: hit.chatId, turnId: hit.turnId, itemId: hit.itemId,
        } });
      } finally {
        if (search === capture) search = undefined;
      }
      await tick();
      transcript?.focus({ preventScroll: true });
    });
  }

  function openArchive(control: HTMLElement | null) {
    archive = { workspaceId: snapshot?.workspace?.workspaceId ?? null, control };
  }

  async function closeArchive() {
    const capture = archive;
    archive = undefined;
    await tick();
    if (capture?.control?.isConnected) capture.control.focus({ preventScroll: true });
    else editor?.focus({ preventScroll: true });
  }

  async function restoreArchived(request: RestoreArchive) {
    if (!archive || actionPending || quit) throw 'staleSelection';
    const capture = archive;
    actionPending = true;
    try {
      await flushEdits();
      if (archive !== capture) throw 'staleSelection';
      await navigateWorkspace({ restoreArchive: request });
    } finally {
      actionPending = false;
    }
  }

  function presentDeletion(request: ConfirmDeleteChat, control: HTMLElement | null) {
    return new Promise<boolean>((complete) => {
      deletion = { request, workspaceId: snapshot?.workspace?.workspaceId ?? null, control, complete };
    });
  }

  async function askChatDeletion(source: DeleteChatSource) {
    if (actionPending || composing || deletion || quit) return false;
    const workspaceId = snapshot?.workspace?.workspaceId ?? null;
    const control = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    actionPending = true;
    try {
      await flushEdits();
      const request = await prepareChatDeletion(source);
      if ((snapshot?.workspace?.workspaceId ?? null) !== workspaceId || quit) {
        await navigateWorkspace({ cancelChatDeletion: request.ticket });
        return false;
      }
      return presentDeletion(request, control);
    } catch (error) {
      if (error !== 'staleSelection' && error !== 'retiredWorkspace') console.error(error);
      return false;
    } finally {
      actionPending = false;
    }
  }

  function settleDeletion(capture: DeletePresentation, confirmed: boolean, restoreFocus: boolean) {
    if (deletion !== capture) return;
    deletion = undefined;
    capture.complete(confirmed);
    if (restoreFocus) void tick().then(() => {
      if (capture.control?.isConnected) capture.control.focus({ preventScroll: true });
      else editor?.focus({ preventScroll: true });
    });
  }

  async function finishDeletion(confirm: boolean) {
    const capture = deletion;
    if (!capture || finishingDeletion || actionPending) return;
    finishingDeletion = true;
    actionPending = true;
    let confirmed = false;
    try {
      const ticket = capture.request.ticket;
      await navigateWorkspace(confirm ? { confirmChatDeletion: ticket } : { cancelChatDeletion: ticket });
      confirmed = confirm;
    } catch (error) {
      if (error !== 'staleSelection' && error !== 'retiredWorkspace') console.error(error);
    } finally {
      settleDeletion(capture, confirmed, true);
      finishingDeletion = false;
      actionPending = false;
    }
  }

  async function updateProjectContext(scope: DraftAttachmentScope, revision: number, change: ProjectContextChange) {
    if (actionPending || composing || quit) throw 'staleSelection';
    actionPending = true;
    try {
      await flushEdits();
      await navigateWorkspace({ editProjectContext: { scope, revision, change } });
      if ('insertPrompt' in change || 'openBookmark' in change) {
        showingProjectContext = false;
        await tick();
        if ('insertPrompt' in change) editor?.focus();
        else transcript?.focus({ preventScroll: true });
      }
    } finally {
      actionPending = false;
    }
  }

  function closeProjectContext() {
    showingProjectContext = false;
    projectContextButton?.focus();
  }

  function acceptText(value: string, inComposition: boolean) {
    text = value;
    if (inComposition || composing || !draftId) return;
    pending = { draftId, text: value };
    void flushEdits()?.catch(console.error);
  }

  async function act(action: () => Promise<unknown>, focusEditor = false) {
    if (actionPending || composing || quit) return;
    actionPending = true;
    try {
      await flushEdits();
      await fileEdits.flush();
      await action();
      if (focusEditor) {
        await tick();
        editor?.focus();
      }
    } catch (error) {
      console.error(error);
    } finally {
      actionPending = false;
    }
  }

  function workspaceAction(action: 'clearProject' | 'newChat' | 'refresh' | 'reconnect' | 'setupSandbox') {
    if (!workspace) return;
    const request = { workspaceId: workspace.workspaceId };
    const intent = { [action]: request } as NavigationIntent;
    void act(async () => {
      await navigateWorkspace(intent);
      if ((action === 'refresh' || action === 'reconnect') && workspaceId === request.workspaceId) {
        checkoutRevision += 1;
      }
    }, action === 'newChat');
  }

  async function changeSidebar(revision: string, change: SidebarChange) {
    if (actionPending || composing || quit) throw 'staleSelection';
    const current = snapshot;
    const open = 'openChat' in change && current?.workspace &&
      current.navigation.sidebar.activeProject === change.openChat.projectId &&
      current.navigation.chats.some((chat) => chat.id === change.openChat.chatId)
      ? { workspaceId: current.workspace.workspaceId, chatId: change.openChat.chatId }
      : undefined;
    actionPending = true;
    try {
      await flushEdits();
      await navigateWorkspace(open ? { openChat: open } : { sidebar: { revision, change } });
    } finally {
      actionPending = false;
    }
  }

  function retryChat() {
    if (!workspace || !navigation?.selectedChat) return;
    const retry = { workspaceId: workspace.workspaceId, chatId: navigation.selectedChat };
    void act(() => navigateWorkspace({ retry }));
  }

  function signIn() {
    const signIn = { workspaceId: workspace?.workspaceId ?? null };
    void act(() => navigateWorkspace({ signIn }));
  }

  function cancelSignIn() {
    const ticket = navigation?.account.loginTicket;
    if (ticket) void act(() => navigateWorkspace({ cancelSignIn: { ticket } }));
  }

  function sendRequest(): SendRequest | undefined {
    if (!workspace || !draftId || !navigation) return;
    return {
      workspaceId: workspace.workspaceId, chatId: navigation.selectedChat, draftId, text,
      attachmentIds: draftAttachments.map((attachment) => attachment.id),
      composerRevision: navigation.composerSettings?.revision ?? null,
      expectedTurn: queue?.activeTurn ?? null,
    };
  }

  async function sendDraft() {
    const send = sendRequest();
    if (!send || !navigation || (!navigation.actions.send && !mayExecuteSlash) ||
        (!text.trim() && !draftAttachments.length && !navigation.projectHasInput) || composing || actionPending) return;
    const literal = navigation.literalForkRevision;
    admittingDraft = true;
    try {
      await act(async () => {
        slashToken = undefined;
        if (literal || !/^[ \t]*\//u.test(send.text) ||
            await applySlash(send, null, false) === 'send') await navigateWorkspace({ send });
      });
    } finally {
      admittingDraft = false;
    }
  }

  async function applySlash(draft: SendRequest, choice: string | null, confirmed: boolean) {
    const outcome = await executeSlashCommand({ draft, choice, confirmed });
    if (outcome === 'send' || outcome === 'applied') {
      commandPanel = undefined;
      return outcome;
    }
    if ('confirmDelete' in outcome) {
      commandPanel = undefined;
      const control = document.activeElement instanceof HTMLElement ? document.activeElement : null;
      void presentDeletion(outcome.confirmDelete, control);
      return 'applied';
    }
    const command = outcome.present;
    if (command === 'diff') {
      preferredComparison = 'uncommitted';
      showingChanges = true;
    } else if (command === 'copy') {
      const latest = snapshot?.transcript.items.filter((row) => row.role === 'assistant' && row.completed && row.text).at(-1);
      if (latest) {
        await copyResponse(latest);
        await executeSlashCommand({ draft, choice: null, confirmed: true });
      }
    } else if (command === 'skills' || command === 'mention') {
      if (attachmentScope?.draftId === draft.draftId && attachmentScope.workspaceId === draft.workspaceId) {
        const caret = editor?.selectionStart ?? draft.text.length;
        contextMenu = { scope: attachmentScope, source: draft.text, query: '', selection: [caret, caret],
          token: null, command };
      }
    } else {
      const inline = command === 'permissions' && /\sfull\s*$/u.test(draft.text);
      commandPanel = { command, draft, fullAccess: inline || choice === 'full', inline };
    }
    return 'applied';
  }

  function finishSlash(choice: string | null, confirmed: boolean) {
    const panel = commandPanel;
    if (!panel) return;
    if (panel.command === 'fork') {
      const chatId = panel.draft.chatId;
      if (!confirmed || !chatId) return;
      const source = { workspaceId: panel.draft.workspaceId, chatId };
      void act(async () => {
        await navigateWorkspace({ recoverFork: { source, fork: choice } });
        commandPanel = undefined;
      }, true);
      return;
    }
    if (panel.command === 'permissions' && choice === 'full' && !confirmed) {
      commandPanel = { ...panel, fullAccess: true };
      return;
    }
    if (panel.command === 'permissions' && panel.fullAccess && !panel.inline && confirmed) choice = 'full';
    void act(() => applySlash(panel.draft, choice, confirmed), true);
  }

  function closeSlashPanel() {
    commandPanel = undefined;
    void tick().then(() => editor?.focus());
  }

  function startReview(target: ReviewTarget, delivery: ReviewDelivery) {
    const panel = commandPanel;
    if (panel?.command !== 'review') return;
    void act(async () => {
      await navigateWorkspace({ startReview: { draft: panel.draft, target, delivery } });
      if (commandPanel === panel) closeSlashPanel();
    }, true);
  }

  function matchSlashToken(control: HTMLTextAreaElement) {
    slashToken = undefined;
    if (!attachmentScope || composing || quit || queue?.editing || navigation?.literalForkRevision ||
        control.selectionStart !== control.selectionEnd) return;
    const match = /^[ \t]*\/([A-Za-z][A-Za-z0-9-]*|)(?=\s|$)/u.exec(control.value);
    const caret = control.selectionStart;
    if (!match) return;
    const end = match[0].length;
    const start = end - match[1]!.length - 1;
    if (caret <= start || caret > end) return;
    slashToken = { start, end, prefix: control.value.slice(start + 1, caret).toLowerCase() };
    slashIndex = 0;
  }

  function completeSlash(command: SlashCommand) {
    if (!slashToken || !editor) return;
    const { start, end } = slashToken;
    const spacer = end === text.length ? ' ' : '';
    const replacement = `/${command}${spacer}`;
    acceptText(text.slice(0, start) + replacement + text.slice(end), false);
    slashToken = undefined;
    void tick().then(() => {
      editor?.focus();
      editor?.setSelectionRange(start + replacement.length, start + replacement.length);
    });
  }

  function composerKey(event: KeyboardEvent) {
    if (event.isComposing || composing) return;
    if (contextMenu?.token && contextPicker?.keyboard(event)) return;
    if (!slashToken) return;
    if (event.key === 'Escape') slashToken = undefined;
    else if (event.key === 'ArrowDown' && slashMatches.length) slashIndex = (slashIndex + 1) % slashMatches.length;
    else if (event.key === 'ArrowUp' && slashMatches.length) slashIndex = (slashIndex + slashMatches.length - 1) % slashMatches.length;
    else if (event.key === 'Tab' && slashMatches[slashIndex]) completeSlash(slashMatches[slashIndex]!);
    else return;
    event.preventDefault();
  }

  function pasteAttachment(event: ClipboardEvent) {
    const scope = attachmentScope;
    if (!scope || queue?.editing || admittingDraft || navigation?.quit) return;
    const images = [...(event.clipboardData?.files ?? [])].filter((file) =>
      file.size <= 20 * 1024 * 1024 && ['image/png', 'image/jpeg', 'image/gif', 'image/webp'].includes(file.type));
    if (!images.length) return;
    event.preventDefault();
    void (async () => {
      for (const image of images.slice(0, 8)) await pasteComposerImage(scope, await image.arrayBuffer());
    })().catch(() => {});
  }

  function showComposerContext() {
    if (contextMenu && !contextMenu.token) { closeComposerContext(); return; }
    if (!editor || !attachmentScope || queue?.editing || quit || composing) return;
    contextMenu = { scope: attachmentScope, source: editor.value, query: '',
      selection: [editor.selectionStart, editor.selectionEnd], token: null };
  }

  function matchComposerToken(control: HTMLTextAreaElement) {
    if (!attachmentScope || queue?.editing || quit || composing ||
        control.selectionStart !== control.selectionEnd || contextMenu && !contextMenu.token) return;
    const caret = control.selectionStart;
    const source = control.value;
    const match = source.slice(0, caret).match(/(?:^|\s)@([^\s@]*)$/u);
    if (!match) { contextMenu = undefined; return; }
    const query = match[1] ?? '';
    const end = caret + (source.slice(caret).match(/^[^\s@]*/u)?.[0].length ?? 0);
    const start = caret - query.length - 1;
    contextMenu = { scope: attachmentScope, source, query, selection: [caret, caret], token: { start, end } };
  }

  function closeComposerContext() {
    const captured = contextMenu;
    contextMenu = undefined;
    if (!captured || captured.scope.draftId !== displayedDraft) return;
    void tick().then(() => {
      if (!editor || captured.scope.draftId !== displayedDraft) return;
      editor.focus();
      editor.setSelectionRange(...captured.selection);
    });
  }

  async function chooseComposerContext(target: ComposerContextTarget) {
    const captured = contextMenu;
    if (!captured || captured.scope.draftId !== displayedDraft || captured.source !== editor?.value ||
        actionPending || quit || composing) return;
    actionPending = true;
    try {
      await flushEdits();
      await addComposerContext({ scope: captured.scope, expectedText: captured.source, replaceToken: captured.token,
        replaceCommand: captured.command ? true : null, target });
      if (captured.scope.draftId !== displayedDraft) return;
      const token = captured.token;
      contextMenu = undefined;
      if (token && text === captured.source) text = captured.source.slice(0, token.start) + captured.source.slice(token.end);
      if (captured.command && text === captured.source) text = '';
      await tick();
      if (!editor || captured.scope.draftId !== displayedDraft) return;
      editor.focus();
      if (captured.command) editor.setSelectionRange(0, 0);
      else editor.setSelectionRange(token?.start ?? captured.selection[0], token?.start ?? captured.selection[1]);
    } catch (error) {
      if (error === 'staleSelection' || error === 'retiredWorkspace') contextMenu = undefined;
    } finally {
      actionPending = false;
    }
  }

  function queueCommand(command: QueueCommand) {
    if (!workspace || !navigation?.selectedChat || !queue || queue.busy) return;
    const request = { workspaceId: workspace.workspaceId, chatId: navigation.selectedChat, revision: queue.revision, command };
    void act(() => navigateWorkspace({ queue: request }), typeof command === 'object' && 'edit' in command);
  }

  function stop() {
    if (!workspace || !stopTarget) return;
    const request = { workspaceId: workspace.workspaceId, target: stopTarget };
    void act(() => navigateWorkspace({ stop: request }));
  }

  function recoverSend() {
    if (!workspace || !draftId) return;
    const request = { workspaceId: workspace.workspaceId, draftId };
    void act(() => navigateWorkspace({ recoverSend: request }));
  }

  function stopLabel() {
    if (stopTarget && 'turn' in stopTarget && stopTarget.turn.threadId !== navigation?.selectedChat) {
      const id = stopTarget.turn.threadId;
      const title = navigation?.chats.find((chat) => chat.id === id)?.title;
      if (title) return `Stop ${title}`;
    }
    return 'Stop';
  }

  function respond(interactionId: string, response: InteractionAnswer) {
    if (!workspace) return;
    const request = { workspaceId: workspace.workspaceId, interactionId, response };
    void act(() => navigateWorkspace({ respond: request }));
  }

  function cancelQuit(ticket: string) {
    return navigateWorkspace({ cancelQuit: { ticket } });
  }

  async function confirmQuit(ticket: string) {
    if (confirmingQuit) return;
    confirmingQuit = true;
    try {
      if (composing && editor) {
        editor.blur();
        composing = false;
        acceptText(editor.value, false);
      }
      await flushEdits();
      if (!quit?.stopOnly) await fileEdits.flush();
      await navigateWorkspace({ confirmQuit: { ticket } });
    } catch (error) {
      console.error(error);
      await cancelQuit(ticket).catch((failure) => {
        if (failure !== 'staleSelection') console.error(failure);
      });
    } finally {
      confirmingQuit = false;
    }
  }

  function handleShortcut(event: KeyboardEvent) {
    if (event.target instanceof HTMLElement && event.target.closest('dialog')) return;
    if (event.key === 'Tab' && !event.defaultPrevented && !event.isComposing) retainSelectionForTab();
    if (event.defaultPrevented || event.isComposing || composing ||
        !(event.metaKey || event.ctrlKey)) return;
    if (event.shiftKey) {
      const key = event.key.toLowerCase();
      if (!event.altKey && key === 'f' && workspace) {
        event.preventDefault();
        if (event.target instanceof Element && event.target.closest('.project-files')) showFileSearch();
        else showMessageSearch();
        return;
      }
      const mode = event.altKey && (event.code === 'KeyO' || key === 'o') ? 'projects' :
        !event.altKey && key === 'p' ? 'commands' : !event.altKey && key === 'k' ? 'chats' : undefined;
      if (mode) {
        event.preventDefault();
        openPalette(mode);
      }
      return;
    }
    if (event.altKey) return;
    switch (event.key.toLowerCase()) {
      case 'p':
        if (attachmentScope) {
          event.preventDefault();
          openPalette('files');
        }
        break;
      case 'o':
        event.preventDefault();
        void act(pickWorkspace);
        break;
      case 'n':
        if (workspace) {
          event.preventDefault();
          workspaceAction('newChat');
        }
        break;
    }
  }

  onMount(() => {
    const lifecycle = new AbortController();
    void observeWorkspace(receive, lifecycle.signal).catch(console.error);
    void voice.observe(lifecycle.signal).catch(console.error);
    void observeDesktop(updateAppearance, (action) => {
      if (action === 'settings' && !quit) settingsOpen = true;
      else if (action === 'undo' || action === 'redo') document.execCommand(action);
      else if (!settingsOpen && action === 'newChat' && workspace) workspaceAction('newChat');
      else if (!settingsOpen && action === 'messageSearch') showMessageSearch();
    }, lifecycle.signal).catch(console.error);
    if (verify === 'account') void verifyAccount(() => snapshot);
    else if (verify === 'settings') void verifySettings(() => snapshot);
    else if (verify === 'appearance' || verify === 'appearanceRestore') void verifyAppearance(verify, () => appearance);
    else if (verify === 'notifications') void verifyNotifications(() => snapshot);
    else if (verify === 'voice') void verifyVoice(() => snapshot, () => call, voice);
    else if (verify === 'voiceHistory' || verify === 'voiceHistoryRestore') void verifyVoiceHistory(verify, () => snapshot);
    else if (verify === 'readAloud') void verifyReadAloud(() => snapshot);
    else if (verify === 'voiceHandoff') void verifyVoiceHandoff(() => snapshot, () => call);
    else if (verify === 'voiceNoFallback') void verifyVoiceNoFallback(() => snapshot, () => call);
    else if (verify === 'voiceReconnect') void verifyVoiceReconnect(() => snapshot, () => call, voice);
    else if (verify === 'windowsSetup') void verifyWindowsSetup(() => snapshot);
    else if (verify === 'turn' || verify === 'activeTurn') void verifyTurn(() => snapshot, verify);
    else if (verify === 'queue') void verifyQueue(() => snapshot);
    else if (verify === 'diff') void verifyDiff(() => snapshot);
    else if (verify === 'quit') void verifyQuit(() => snapshot);
    else if (verify === 'attachments') void verifyComposerAttachments(() => snapshot);
    else if (verify === 'annotations') void verifyImageAnnotations(() => snapshot);
    else if (verify === 'composerContext') void verifyComposerContext(() => snapshot);
    else if (verify === 'composerSettings') void verifyComposerSettings(() => snapshot);
    else if (verify === 'projectContext') void verifyProjectContext(() => snapshot);
    else if (verify === 'slashCommands') void verifySlashCommands(() => snapshot);
    else if (verify === 'promptRevision') void verifyPromptRevision(() => snapshot);
    else if (verify === 'conversationFork') void verifyConversationFork(() => snapshot);
    else if (verify === 'sidebar' || verify === 'sidebarRestore') void verifySidebar(verify, () => snapshot);
    else if (verify === 'commandPalette') void verifyCommandPalette(() => snapshot);
    else if (verify === 'archive') void verifyArchive(() => snapshot);
    else if (verify === 'chatDeletion') void verifyChatDeletion(() => snapshot);
    else if (verify === 'messageSearch') void verifyMessageSearch(() => snapshot, searchIndex);
    else if (verify === 'automaticTitles') void verifyAutomaticTitles(() => snapshot);
    else if (verify === 'pinnedSummary') void verifyPinnedSummary(() => snapshot);
    else if (verify === 'inspector') void verifyInspector(() => snapshot);
    else if (verify === 'feedback') void verifyFeedback(() => snapshot);
    else if (verify === 'fileTools') void verifyFileTools(() => snapshot);
    else if (verify) void verifyHistory(verify, () => snapshot);
    return () => lifecycle.abort();
  });

  function updateAppearance(view: AppearanceView) {
    appearance = view;
    applyDesktopAppearance(view);
  }
</script>

<svelte:window onkeydown={handleShortcut} />

<main class="workspace" aria-label="Codex GUI">
  <header class="workspace-header">
    <button type="button" disabled={actionPending} onclick={() => void act(pickWorkspace)}>Open Project…</button>
    <button type="button" bind:this={settingsButton} disabled={actionPending || !!quit}
      aria-haspopup="dialog" onclick={() => { settingsOpen = true; }}>Settings</button>
    <button type="button" disabled={actionPending || !!quit} aria-keyshortcuts="Meta+Shift+P Control+Shift+P"
      onclick={() => openPalette('commands')}>Command Palette</button>
    <button type="button" disabled={actionPending || !!quit} aria-keyshortcuts="Meta+Alt+Shift+O Control+Alt+Shift+O"
      onclick={() => openPalette('projects')}>Choose Project</button>
    {#if sidebar?.chats.length}
      <button type="button" disabled={actionPending || !!quit} aria-keyshortcuts="Meta+Shift+K Control+Shift+K"
        onclick={() => openPalette('chats')}>Choose Chat</button>
    {/if}
    <button type="button" disabled={actionPending || !!quit}
      onclick={(event) => openArchive(event.currentTarget)}>Archived Chats</button>
    {#if navigation?.actions.stopAll}
      <button type="button" disabled={actionPending || !!quit}
        onclick={() => void act(() => navigateWorkspace('stopAll'))}>Stop All…</button>
    {/if}
    {#if workspace}
      <h1 title={workspace.projectPath}>{projectTitle ?? workspace.projectPath}</h1>
      <button type="button" disabled={actionPending} onclick={() => workspaceAction('clearProject')}>Clear Project</button>
      <button type="button" disabled={actionPending} onclick={() => workspaceAction('refresh')}>Refresh</button>
      <button type="button" disabled={actionPending} onclick={() => workspaceAction('reconnect')}>Reconnect</button>
      <button type="button" disabled={actionPending || !!quit} aria-keyshortcuts="Meta+Shift+F Control+Shift+F"
        onclick={showMessageSearch}>Search Messages</button>
      <button type="button" aria-expanded={showingChanges}
        onclick={() => { preferredComparison = 'uncommitted'; showingChanges = !showingChanges; }}>Changes</button>
      {#if attachmentScope}
        <button type="button" aria-expanded={filesOpened} disabled={!!quit} onclick={() => void filePane?.toggle()}>Files</button>
        <button type="button" aria-keyshortcuts="Meta+P Control+P" disabled={actionPending || !!quit}
          onclick={() => openPalette('files')}>Quick Open</button>
        <button type="button" disabled={actionPending || !!quit} onclick={showFileSearch}>Search Files</button>
      {/if}
      {#if summaryScope}
        <button type="button" aria-expanded={summaryVisible} disabled={!!quit} onclick={toggleSummary}>Pinned Summary</button>
        {@const scope = summaryScope}
        <button type="button" aria-expanded={inspector?.opened && inspector.selection.tab === 'sources'}
          disabled={!!quit} onclick={() => openInspector(scope, 'sources')}>Sources</button>
        <button type="button" aria-expanded={inspector?.opened && inspector.selection.tab === 'commands'}
          disabled={!!quit} onclick={() => openInspector(scope, 'commands')}>Commands</button>
        {#if navigation?.inspector.agents.length}
          <button type="button" aria-expanded={inspector?.opened && inspector.selection.tab === 'subagents'}
            disabled={!!quit} onclick={() => openInspector(scope, 'subagents')}>Subagents</button>
        {/if}
      {/if}
      {#if navigation?.canFork || navigation?.recoverFork}
        <button type="button" disabled={actionPending} onclick={forkChat}>
          {navigation.recoverFork ? 'Resolve Fork' : 'Fork Chat'}
        </button>
      {/if}
      <button type="button" bind:this={projectContextButton} aria-expanded={showingProjectContext}
        disabled={!attachmentScope || !!quit}
        onclick={() => { showingProjectContext = !showingProjectContext; }}>Project Context</button>
    {/if}
    {#if navigation?.writeAccess === 'setupSandbox' || navigation?.writeAccess === 'settingUpSandbox'}
      <button type="button" disabled={actionPending || navigation.writeAccess === 'settingUpSandbox'}
        onclick={() => workspaceAction('setupSandbox')}>Set Up Sandbox</button>
    {:else if navigation?.writeAccess === 'updateSandbox' || navigation?.writeAccess === 'updatingSandbox'}
      <button type="button" disabled={actionPending || navigation.writeAccess === 'updatingSandbox'}
        onclick={() => workspaceAction('setupSandbox')}>Update Sandbox</button>
    {/if}
    {#if navigation?.account.loginTicket}
      <button type="button" disabled={actionPending} onclick={cancelSignIn}>Cancel Sign-in</button>
    {:else if !navigation?.account.identity}
      <button type="button" disabled={actionPending} onclick={signIn}>Sign In</button>
    {/if}
  </header>

  <div class="workspace-body">
    {#if sidebar && (workspace || sidebar.projects.length)}
      <nav class="workspace-sidebar" aria-label={workspace ? 'Chats' : 'Projects'}>
        <WorkspaceSidebar view={sidebar} {selectedChat} blocked={actionPending || !!quit}
          newChat={workspace ? () => workspaceAction('newChat') : undefined} change={changeSidebar}
          deleteChat={(revision, key) => askChatDeletion({ sidebar: { revision, key } })}
          reveal={(revision, projectId) => revealSidebarProject({ revision, projectId })} />
      </nav>
    {/if}
    <section class="workspace-conversation" aria-label="Conversation">
      {#if summaryScope && summaryVisible && !quit}
        {@const scope = summaryScope}
        {#key JSON.stringify([scope.workspaceId, scope.chatId])}
          <PinnedSummary {scope} lastTurn={navigation?.lastTurn} {checkoutRevision} sources={recentSources()}
            agentCount={navigation?.inspector.agents.length ?? 0} openChanges={() => openSummaryChanges(scope)}
            openSource={(id) => openInspector(scope, 'sources', id)}
            openAgents={() => openInspector(scope, 'subagents')} />
        {/key}
      {/if}
      <div class="transcript-pane">
        <!-- svelte-ignore a11y_no_noninteractive_tabindex, a11y_no_noninteractive_element_interactions (The named scrolling region needs keyboard focus and scroll input.) -->
        <div class="workspace-transcript" role="region" aria-label="Transcript" tabindex="0" bind:this={transcript} use:attachTranscript
          onwheel={transcriptWheel} onkeydown={transcriptKey} onscroll={transcriptScroll}>
          {#each viewport.entries as entry (entry.key)}
            {#if 'item' in entry}
              {@const response = entry.item.role === 'assistant' && entry.item.completed && !!entry.item.text.trim() && finishedTurns.has(entry.item.turnId)}
              {@const request = rowRequest(entry.item)}
              <div class="transcript-row-slot" data-transcript-slot={entry.item.itemId} use:measureTranscriptRow>
                <TranscriptRow item={entry.item} {request} attachmentScope={queue?.editing ? undefined : attachmentScope} copy={copyResponse}
                  onCopyFocus={focusResponseAction} edit={editablePrompts.has(entry.item.itemId) ? editSentPrompt : undefined}
                  branch={response && navigation?.canFork ? branchResponse : undefined}
                  bookmark={response && !entry.item.spoken ? setResponseBookmark : undefined}
                  feedback={request && feedbackRows.has(entry.item.itemId) ? (rating) => sendFeedback(request, rating) : undefined}
                  readAloud={request && response && !entry.item.spoken && speechAvailable && entry.item.text.length <= 256 * 1024 ? readResponse : undefined}
                  reading={reading?.row.itemId === entry.item.itemId}
                  bookmarked={responseBookmarks.has(entry.item.itemId)} />
              </div>
            {:else}
              <div style:block-size={`${entry.gap}px`} aria-hidden="true"></div>
            {/if}
          {/each}
        </div>
        {#if workspace && navigation?.selectedChat && navigation.turnRail?.turns.length}
          {#key navigation.turnRail.id}
            <TurnRail rail={navigation.turnRail} workspaceId={workspace.workspaceId} chatId={navigation.selectedChat} />
          {/key}
        {/if}
      </div>
      {#if navigation?.olderHistory?.speech}
        <button type="button" disabled={navigation.olderHistory.pending} onclick={requestOlderHistory}>Load Earlier Messages</button>
      {/if}
      {#if navigation?.retryable && navigation.writeAccess === 'ready'}
        <button class="workspace-retry" type="button" disabled={actionPending} onclick={retryChat}>Retry</button>
      {/if}
      {#each navigation?.actions.interactions ?? [] as interaction (interaction.id)}
        <InteractionCard {interaction} disabled={actionPending} respond={(answer) => respond(interaction.id, answer)} />
      {/each}
      {#if queue}
        <QueuePanel {queue} disabled={actionPending || queue.busy || !!quit}
          draftOccupied={text !== '' || !!draftAttachments.length || !!queue.editing} command={queueCommand} />
      {/if}
      {#if call && voiceInline}
        {@const id = call.id}
        <VoiceControls {call} floating={false}
          mute={(microphone, muted) => void voice.mute(id, microphone, muted).catch(console.error)}
          end={() => void voice.end(id).catch(console.error)} />
      {/if}
      {#if navigation?.draft}
        {#if attachmentScope && draftAttachments.length && !queue?.editing}
          {#key attachmentScope.draftId}
            <ComposerAttachments scope={attachmentScope} attachments={draftAttachments} />
          {/key}
        {/if}
        <textarea class="workspace-composer" aria-label="Message" rows="4" bind:this={editor}
          onpaste={pasteAttachment}
          onkeydown={composerKey}
          onclick={(event) => matchSlashToken(event.currentTarget)}
          readonly={admittingDraft || confirmingQuit || quit?.draining}
          value={text} oncompositionstart={() => { composing = true; }}
          oncompositionend={(event) => {
            composing = false;
            acceptText(event.currentTarget.value, false);
            matchComposerToken(event.currentTarget);
            matchSlashToken(event.currentTarget);
          }}
          oninput={(event) => {
            const marked = event instanceof InputEvent && event.isComposing;
            acceptText(event.currentTarget.value, marked);
            if (!marked) {
              matchComposerToken(event.currentTarget);
              matchSlashToken(event.currentTarget);
            }
          }}></textarea>
        {#if slashMatches.length}
          <div class="slash-completion" role="group" aria-label="Composer Commands">
            {#each slashMatches as command, index (command)}
              <button type="button" aria-current={index === slashIndex ? 'true' : undefined}
                onclick={() => completeSlash(command)}>/{command}</button>
            {/each}
          </div>
        {/if}
        {#if contextMenu}
          {#key `${contextMenu.scope.draftId}/${contextMenu.token ? 'token' : 'button'}`}
            <ComposerContextPicker bind:this={contextPicker} scope={contextMenu.scope} fromButton={!contextMenu.token}
              skillsOnly={contextMenu.command === 'skills'} initialQuery={contextMenu.query}
              choose={(target) => void chooseComposerContext(target)} close={closeComposerContext} />
          {/key}
        {/if}
        {#if attachmentScope && navigation.composerSettings}
          {#key attachmentScope.draftId}
            <ComposerSettingsControls scope={attachmentScope} view={navigation.composerSettings}
              hiddenEfforts={navigation.hiddenReasoningEfforts}
              models={navigation.account.models} disabled={!!queue?.editing || !!quit}
              workspaceLabel={workspace?.projectPath ?? ''} />
          {/key}
        {/if}
        <div class="composer-actions">
          {#if queue}
            <button type="button" aria-pressed={queue.enabled}
              disabled={actionPending || queue.busy} onclick={() => queueCommand({ enable: !queue.enabled })}>
              Queue Follow-ups
            </button>
          {/if}
          {#if navigation.actions.recover}
            <button type="button" disabled={actionPending} onclick={recoverSend}>Recover Send</button>
          {/if}
          {#if stopTarget}
            <button type="button" disabled={actionPending} onclick={stop}>{stopLabel()}</button>
          {/if}
          {#if queue?.editing}
            {@const edit = queue.editing}
            <button type="button" disabled={actionPending || queue.busy}
              onclick={() => queueCommand({ cancelEdit: edit.id })}>Cancel Edit</button>
            <button type="button" disabled={actionPending || queue.busy || (!text.trim() && !edit.hasContext)}
              onclick={() => queueCommand({ saveEdit: edit.id })}>Save Queue Edit</button>
          {:else if resumeCommand && text === '' && !draftAttachments.length}
            <button type="button" disabled={actionPending || queue?.busy}
              onclick={() => { if (resumeCommand) queueCommand(resumeCommand); }}>Resume</button>
          {:else}
            {#if attachmentScope}
              {@const scope = attachmentScope}
              <button type="button" disabled={actionPending || !!navigation.quit} aria-expanded={!!contextMenu}
                onclick={showComposerContext}>Add Context</button>
              <button type="button" disabled={actionPending || !!navigation.quit}
                onclick={() => { void pickComposerAttachments(scope).catch(() => {}); }}>Attach Files</button>
            {/if}
            {#if !call && navigation.voiceAvailable && attachmentScope && !stopTarget && !quit &&
                !text.trim() && !draftAttachments.length && !navigation.projectHasInput}
              {@const scope = attachmentScope}
              <button type="button" disabled={actionPending || admittingDraft}
                onclick={() => { if (!composing) void voice.start({ ...scope, reconnect: reconnectHere }, flushEdits); }}>
                {reconnectHere ? 'Reconnect Voice Call' : 'Start Voice Call'}
              </button>
            {:else}
              <button type="button" disabled={actionPending || (!navigation.actions.send && !mayExecuteSlash) ||
                (!text.trim() && !draftAttachments.length && !navigation.projectHasInput)} onclick={() => void sendDraft()}>
                {queue?.activeTurn ? (queue.enabled ? 'Queue' : 'Steer') : 'Send'}
              </button>
            {/if}
          {/if}
        </div>
      {/if}
    </section>
    {#if showingChanges && attachmentScope}
      {#key JSON.stringify([attachmentScope.workspaceId, attachmentScope.chatId, attachmentScope.draftId])}
        <WorkspaceChanges scope={attachmentScope} preferred={preferredComparison}
          lastTurnId={navigation?.lastTurn?.turnId} lastTurnRevision={navigation?.lastTurn?.revision} />
      {/key}
    {/if}
    {#if attachmentScope}
      {#key JSON.stringify([attachmentScope.workspaceId, attachmentScope.draftId])}
        <WorkspaceFiles scope={attachmentScope} edits={fileEdits} positions={filePositions}
          revision={navigation?.fileRevision ?? 0} blocked={!!quit} bind:opened={filesOpened} bind:this={filePane} />
      {/key}
    {/if}
    {#if summaryScope && inspector?.opened && navigation && !quit}
      {@const scope = summaryScope}
      {@const selection = inspector.selection}
      {#key JSON.stringify([scope.workspaceId, scope.chatId])}
        <ConversationInspector {scope} {selection} view={navigation.inspector}
          attachments={selection.tab === 'sources' ? recentSources(96) : []}
          commands={selection.tab === 'commands' ? snapshot?.transcript.items.flatMap((item) => item.commands) ?? [] : []}
          choose={(next) => updateInspector(scope, next)} close={() => updateInspector(scope, selection, false)} />
      {/key}
    {/if}
    {#if showingProjectContext && attachmentScope && navigation}
      {#key `${attachmentScope.workspaceId}/${attachmentScope.draftId}`}
        <ProjectContextPanel scope={attachmentScope} models={navigation.account.models} draftText={text}
          hiddenEfforts={navigation.hiddenReasoningEfforts}
          bookmarkKey={navigation.bookmarkedResponses.join('\n')}
          blocked={actionPending || !!queue?.editing || !!quit} submit={updateProjectContext} close={closeProjectContext} />
      {/key}
    {/if}
  </div>
  {#if commandPanel && workspace && navigation}
    {#if commandPanel.command === 'review'}
      <ReviewPanel source={commandPanel.draft.text} blocked={actionPending} submit={startReview} close={closeSlashPanel} />
    {:else}
      <SlashCommandPanel command={commandPanel.command} fullAccess={commandPanel.fullAccess}
      sourceId={commandPanel.draft.chatId}
      chats={navigation.chats} models={navigation.account.models} usage={navigation.slashCommands.context}
      workspace={workspace.projectPath} chat={navigation.chats.find((chat) => chat.id === selectedChat)?.title}
      effective={navigation.account.models.find((model) => model.id === navigation.composerSettings?.effectiveModelId)}
      hiddenEfforts={navigation.hiddenReasoningEfforts} selectedEffort={navigation.composerSettings?.selection.effort}
      choose={finishSlash} close={closeSlashPanel} />
    {/if}
  {/if}
  {#if settingsOpen && !quit}
    <SettingsWindow workspaceId={workspaceId ?? null} syntheticSpeech={verify === 'voice'} accountBusy={!!navigation?.actions.stopAll || !!navigation?.account.loginTicket}
      {appearance} appearanceChanged={updateAppearance}
      close={() => { settingsOpen = false; void tick().then(() => settingsButton.focus({ preventScroll: true })); }} />
  {/if}
  {#if promptEdit}
    {#key promptEdit.view.ticket}
      <SentPromptDialog prompt={promptEdit.view} applying={actionPending} submit={reviseSentPrompt} cancel={cancelSentPromptEdit} />
    {/key}
  {/if}
  {#if palette}
    {#key palette.mode}
      <CommandPalette mode={palette.mode} entries={palette.entries} blocked={actionPending}
        lookup={palette.mode === 'files' ? lookupPaletteFiles : undefined}
        choose={(entry) => void choosePalette(entry)} close={closePalette} />
    {/key}
  {/if}
  {#if fileSearch}
    <FileSearch scope={fileSearch.scope} blocked={actionPending} choose={(hit) => void chooseFileSearch(hit)} close={closeFileSearch} />
  {/if}
  {#if archive}
    <ArchivedChats workspaceId={archive.workspaceId} restore={restoreArchived} close={closeArchive}
      deleteChat={(revision, chatId) => askChatDeletion({ archive: { revision, chatId } })} />
  {/if}
  {#if deletion}
    <DeleteChatDialog title={deletion.request.title} busy={finishingDeletion}
      cancel={() => void finishDeletion(false)} confirm={() => void finishDeletion(true)} />
  {/if}
  {#if search}
    <MessageSearch index={searchIndex} revision={searchRevision} blocked={actionPending}
      load={loadSearchPage} choose={chooseSearchHit} close={closeSearch} />
  {/if}
  {#if quit?.confirm && !quit.draining}
    <QuitDialog busy={confirmingQuit} savingFiles={!quit.stopOnly && !!navigation?.savingFiles} stopOnly={quit.stopOnly} fileAction={quit.fileAction}
      cancel={() => { if (quit) void cancelQuit(quit.ticket).catch(console.error); }}
      confirm={() => { if (quit) void confirmQuit(quit.ticket); }} />
  {/if}
  {#if call && !voiceInline}
    {@const id = call.id}
    <VoiceControls {call} floating={true}
      mute={(microphone, muted) => void voice.mute(id, microphone, muted).catch(console.error)}
      end={() => void voice.end(id).catch(console.error)} />
  {/if}
</main>
