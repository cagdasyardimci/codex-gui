import type { NavigationView, SidebarChatKey } from './generated/workspace';

export type PaletteMode = 'commands' | 'projects' | 'chats';
export type PaletteAction = 'browse' | 'newChat' | 'changes' | 'projectContext' | 'refresh' | 'reconnect' | 'archivedChats' | 'messageSearch';

type PaletteDestination =
  | { project: string }
  | { chat: SidebarChatKey }
  | { action: PaletteAction };

export type PaletteEntry = {
  id: string;
  title: string;
  detail?: string;
  destination: PaletteDestination;
};

export function paletteEntries(mode: PaletteMode, navigation: NavigationView): PaletteEntry[] {
  const sidebar = navigation.sidebar;
  const projects: PaletteEntry[] = sidebar.projects.map((project) => ({
    id: `project/${project.id}`, title: project.title, detail: project.path, destination: { project: project.id },
  }));
  const projectNames = new Map(sidebar.projects.map((project) => [project.id, project.title]));
  const chats: PaletteEntry[] = sidebar.chats.map((chat) => ({
    id: `chat/${JSON.stringify(chat.key)}`, title: chat.title,
    detail: projectNames.get(chat.key.projectId), destination: { chat: chat.key },
  }));
  const browse: PaletteEntry = { id: 'action/browse', title: 'Open Project…', destination: { action: 'browse' } };
  if (mode === 'projects') return [...projects, browse];
  if (mode === 'chats') return chats;

  const actions: PaletteEntry[] = [
    browse,
    { id: 'action/archivedChats', title: 'Archived Chats', destination: { action: 'archivedChats' } },
  ];
  if (sidebar.activeProject) {
    const workspaceActions: Array<[PaletteAction, string]> = [
      ['newChat', 'New Chat'],
      ['changes', 'Changes'],
      ['projectContext', 'Project Context'],
      ['messageSearch', 'Search Messages'],
      ['refresh', 'Refresh'],
      ['reconnect', 'Reconnect'],
    ];
    for (const [action, title] of workspaceActions) {
      actions.push({ id: `action/${action}`, title, destination: { action } });
    }
  }
  return [...actions, ...projects, ...chats];
}

function searchable(value: string) {
  return value.normalize('NFKD').replace(/\p{M}/gu, '').toLowerCase();
}

export function filterPalette(entries: PaletteEntry[], input: string): PaletteEntry[] {
  const query = searchable(input).trim();
  if (!query) return entries.slice(0, 80);
  const terms = query.split(/\s+/u);
  const matches: Array<{ entry: PaletteEntry; rank: number }> = [];
  for (const entry of entries) {
    const title = searchable(entry.title);
    const detail = searchable(entry.detail ?? '');
    if (!terms.every((term) => title.includes(term) || detail.includes(term))) continue;
    const rank = title.startsWith(query) ? 0 : title.includes(query) ? 1 : 2;
    matches.push({ entry, rank });
  }
  return matches.sort((first, second) => first.rank - second.rank).slice(0, 80).map(({ entry }) => entry);
}
