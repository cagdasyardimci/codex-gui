import { invoke } from '@tauri-apps/api/core';
import type { WorkspaceSnapshot } from './generated/workspace';
import { click, typeText, waitFor } from './fixtureControls';
import { rejectsStale } from './markdownProbe';
import { navigateWorkspace, revealSidebarProject } from './projectIpc';

const FIRST = 'history-first';
const SECOND = 'history-second';
const PRIMARY = 'Primary design';
const CHAT = 'Renamed fixture chat';
const FINAL_CHAT = 'Final fixture chat';
const DRAFT = 'Independent original project draft.';
const OTHER_DRAFT = 'Independent other project draft.';

export async function verifySidebar(
  mode: 'sidebar' | 'sidebarRestore',
  visible: () => WorkspaceSnapshot | null,
) {
  const view = () => visible()?.navigation.sidebar;
  const selected = () => visible()?.navigation.selectedChat;
  const draft = () => visible()?.navigation.draft?.text;
  const rows = () => view()?.chats ?? [];
  const own = () => rows().filter((chat) => chat.key.projectId === view()?.activeProject);
  const chat = (id: string) => document.querySelector<HTMLElement>(`[data-sidebar-chat="${CSS.escape(id)}"]`);
  const project = (id: string) => document.querySelector<HTMLElement>(`[data-sidebar-project="${CSS.escape(id)}"]`);
  const saveDraft = async (text: string) => {
    typeText(text);
    await waitFor('The selected chat did not preserve its draft', () => draft() === text);
  };
  try {
    await waitFor('The registered projects and scoped chat list did not load', () => !!view()?.activeProject && own().length === 2);
    const primary = view()!.activeProject!;
    if (mode === 'sidebarRestore') {
      await waitFor('Restart did not restore the project and captured chat together', () =>
        selected() === FIRST && draft() === DRAFT && view()?.group === 'oneList' && view()?.sort === 'manual' &&
        view()?.projects.find((project) => project.id === primary)?.title === PRIMARY &&
        view()?.projects.find((project) => project.id === primary)?.pinned === true &&
        rows().find((chat) => chat.key.chatId === FIRST)?.title === FINAL_CHAT &&
        rows().find((chat) => chat.key.chatId === FIRST)?.pinned === true &&
        rows().find((chat) => chat.key.chatId === SECOND)?.unread === true &&
        rows().some((chat) => chat.key.chatId === 'other-history-first'));
      await invoke('verify_attachments_result', { failure: null });
      return;
    }

    const workspace = visible()!.workspace!;
    const primaryPath = view()!.projects.find((project) => project.id === primary)!.path;
    const startingRevision = view()!.revision!;
    if (own().map((row) => row.key.chatId).join() !== `${SECOND},${FIRST}`) {
      throw new Error('The sidebar did not sort by backend update time');
    }
    await chooseOption('Sort Chats', 'manual');
    await waitFor('Manual sort did not apply', () => view()?.sort === 'manual');
    const source = chat(FIRST)?.querySelector('button.chat-row');
    const target = chat(SECOND)?.querySelector('button.chat-row');
    if (!source || !target) throw new Error('Manual drag could not find the scoped rows');
    dragChat(source, target);
    await waitFor('Dragging a chat did not persist its new manual position', () => own()[0]?.key.chatId === FIRST);
    dragChat(source, target, true);
    await waitFor('Dragging below a row did not place the chat last', () => own()[1]?.key.chatId === FIRST);
    dragChat(source, target);
    await waitFor('Dragging above a row did not restore the manual position', () => own()[0]?.key.chatId === FIRST);

    await rowAction(() => project(primary), 'Rename Project');
    await rename('Rename Project', PRIMARY);
    await waitFor('Project rename changed its identity or path', () =>
      view()?.projects.find((project) => project.id === primary)?.title === PRIMARY &&
      visible()?.workspace?.workspaceId === workspace.workspaceId && visible()?.workspace?.projectPath === workspace.projectPath);
    await rowAction(() => project(primary), 'Pin Project');
    await waitFor('The project was not pinned', () => project(primary)?.closest('section')?.getAttribute('aria-label') === 'Pinned');
    await revealSidebarProject({ revision: view()!.revision!, projectId: primary });
    await rejectsStale(revealSidebarProject({ revision: startingRevision, projectId: primary }));

    await click('First fixture chat');
    await waitFor('The scoped chat was not selected', () => selected() === FIRST);
    await rowAction(() => chat(FIRST), 'Rename Chat');
    await rename('Rename Chat', CHAT);
    await waitFor('Chat rename changed scope or targeted a different chat', () =>
      selected() === FIRST && own().find((chat) => chat.key.chatId === FIRST)?.title === CHAT);
    await saveDraft(`/rename ${FINAL_CHAT}`);
    await click('Send');
    await waitFor('The slash rename did not reach the same chat workflow', () =>
      selected() === FIRST && own().find((chat) => chat.key.chatId === FIRST)?.title === FINAL_CHAT && draft() === '');
    await saveDraft(DRAFT);
    await rowAction(() => chat(FIRST), 'Pin Chat');
    await waitFor('The chat was not pinned', () => own().find((chat) => chat.key.chatId === FIRST)?.pinned === true);
    await rowAction(() => chat(SECOND), 'Mark Unread');
    await waitFor('The unread mark did not persist on the captured chat', () =>
      own().find((chat) => chat.key.chatId === SECOND)?.unread === true);

    await invoke('select_fixture_checkout', { secondary: true });
    await waitFor('The other checkout did not get a distinct sidebar identity', () =>
      !!view()?.activeProject && view()?.activeProject !== primary && own().some((chat) => chat.key.chatId === 'other-history-first'));
    const secondary = view()!.activeProject!;
    await click('Other First fixture chat');
    await waitFor('The other project chat did not select', () => selected() === 'other-history-first');
    await saveDraft(OTHER_DRAFT);
    await click(FINAL_CHAT);
    await waitFor('Opening the pinned chat used a different project or draft', () =>
      view()?.activeProject === primary && selected() === FIRST && draft() === DRAFT &&
      visible()?.workspace?.projectPath === primaryPath && visible()?.workspace?.workspaceId !== workspace.workspaceId);
    await chooseOption('Organize Sidebar', 'oneList');
    await waitFor('The combined list did not retain both project identities', () =>
      view()?.group === 'oneList' && !!chat('other-history-first') && view()?.projects.length === 2);
    await click('Other First fixture chat');
    await waitFor('Opening a cross-project recent lost its draft or checkout', () =>
      view()?.activeProject === secondary && selected() === 'other-history-first' && draft() === OTHER_DRAFT);
    await click(FINAL_CHAT);
    await waitFor('The pinned chat did not recover its exact owner', () =>
      selected() === FIRST && view()?.activeProject === primary && draft() === DRAFT);
    await rejectsStale(navigateWorkspace({ sidebar: { revision: view()!.revision!, change: {
      openChat: { projectId: secondary, chatId: FIRST },
    } } }));
    await invoke('verify_attachments_result', { failure: null });
  } catch (error) {
    await invoke('verify_attachments_result', { failure: String(error) });
  }
}

function dragChat(source: Element, target: Element, after = false) {
  const transfer = new DataTransfer();
  const bounds = target.getBoundingClientRect();
  const clientY = after ? Math.ceil(bounds.bottom) : Math.floor(bounds.top);
  const options = { dataTransfer: transfer, cancelable: true, bubbles: true, clientY };
  source.dispatchEvent(new DragEvent('dragstart', options));
  target.dispatchEvent(new DragEvent('dragover', options));
  target.dispatchEvent(new DragEvent('drop', options));
}

async function chooseOption(name: string, value: string) {
  const select = () => document.querySelector<HTMLSelectElement>(`select[aria-label="${CSS.escape(name)}"]:enabled`);
  await waitFor(`The sidebar did not offer ${name}`, () => !!select());
  const field = select()!;
  const menu = field.closest('details');
  if (menu) menu.open = true;
  field.value = value;
  field.dispatchEvent(new Event('change', { bubbles: true }));
}

async function rowAction(row: () => HTMLElement | null, label: string) {
  const button = () => [...(row()?.querySelectorAll<HTMLButtonElement>('details button:enabled') ?? [])]
    .find((button) => button.textContent?.trim() === label);
  await waitFor(`The scoped row did not offer ${label}`, () => !!button());
  row()?.querySelector('summary')?.click();
  button()?.click();
}

async function rename(title: string, value: string) {
  const field = () => document.querySelector<HTMLInputElement>(`dialog[aria-label="${CSS.escape(title)}"][open] input`);
  await waitFor(`The scoped ${title} dialog did not open`, () => !!field());
  field()!.value = value;
  field()!.dispatchEvent(new Event('input', { bubbles: true }));
  await click('Save Name');
  await waitFor(`The ${title} dialog did not commit`, () => !field());
}
