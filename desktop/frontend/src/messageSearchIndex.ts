import type { MessageSearchPage, TranscriptItem, WorkspaceSnapshot, WorkspaceUpdate } from './generated/workspace';

type SearchText = { original: string; folded: string };
type Entry = { itemId: string; turnId: string; content: SearchText[]; cost: number };
type Chat = {
  title: string;
  rows: Map<string, Entry>;
  visibleTurns: Set<string>;
  covered: boolean;
  earlier: boolean;
  partial: boolean;
  cost: number;
};

export type SearchHit = {
  chatId: string;
  chatTitle: string;
  turnId: string;
  itemId: string;
  before: string;
  match: string;
  after: string;
};

const MAX_CHAT_COST = 400_000;
const MAX_INDEX_COST = 1_600_000;
const MAX_RESULTS = 180;

function foldCharacter(value: string) {
  return value.normalize('NFKD').replace(/\p{M}/gu, '').toLowerCase();
}

function fold(value: string) {
  let result = '';
  for (const character of value) result += foldCharacter(character);
  return result;
}

function body(row: TranscriptItem): string[] {
  if (row.role !== 'commands') return row.completed && row.text ? [row.text] : [];
  return row.commands.flatMap((command) => command.completed ? [command.command, command.output ?? ''].filter(Boolean) : []);
}

function snippet(original: string, location: number, length: number) {
  let begin = 0;
  let end = 0;
  let offset = 0;
  let index = 0;
  for (const character of original) {
    const next = offset + foldCharacter(character).length;
    if (offset >= location + length && next > offset) break;
    if (next <= location) begin = index + character.length;
    index += character.length;
    end = index;
    offset = next;
  }
  const left = Array.from(original.slice(Math.max(0, begin - 124), begin)).slice(-60).join('');
  const right = Array.from(original.slice(end, end + 204)).slice(0, 100).join('');
  return {
    before: (left.length < begin ? '…' : '') + left,
    match: original.slice(begin, end),
    after: right + (end + right.length < original.length ? '…' : ''),
  };
}

export class MessageSearchIndex {
  #workspace: string | null = null;
  #sidebar: string | null = null;
  #chats = new Map<string, Chat>();
  #cost = 0;
  revision = 0;

  observe(snapshot: WorkspaceSnapshot, change?: WorkspaceUpdate) {
    const workspace = snapshot.workspace?.workspaceId ?? null;
    if (workspace !== this.#workspace) {
      this.#workspace = workspace;
      this.#sidebar = null;
      this.#chats.clear();
      this.#cost = 0;
      this.revision += 1;
    }
    if (!workspace) return;
    this.#syncChats(snapshot);
    const selected = snapshot.navigation.selectedChat;
    const chat = selected ? this.#chats.get(selected) : undefined;
    if (!chat) return;
    if (!change || typeof change === 'object' && 'changed' in change) {
      if (!snapshot.navigation.turnRail) return;
      const visible = new Set(snapshot.transcript.items.map((row) => row.turnId));
      const retired = [...chat.visibleTurns].filter((turn) => !visible.has(turn));
      this.#evict(chat, retired);
      if (snapshot.transcript.hasEvictedTurns) this.#partial(chat);
      for (const row of snapshot.transcript.items) this.#upsert(chat, row);
      chat.visibleTurns = visible;
      this.#cover(chat, !!snapshot.navigation.olderHistory);
      return;
    }
    if (typeof change !== 'object') return;
    if ('history' in change) {
      for (const insertion of change.history.insertions) {
        for (const row of insertion.rows) {
          chat.visibleTurns.add(row.turnId);
          this.#upsert(chat, row);
        }
      }
      this.#evict(chat, change.history.evictedTurns);
      this.#cover(chat, !!snapshot.navigation.olderHistory);
    } else if ('stream' in change) {
      const event = change.stream.change;
      if (typeof event === 'object') {
        const row = 'finalItem' in event ? event.finalItem : 'itemCompleted' in event ?
          snapshot.transcript.items.find((item) => item.itemId === event.itemCompleted) : undefined;
        if (row) {
          chat.visibleTurns.add(row.turnId);
          this.#upsert(chat, row);
        }
      }
      this.#evict(chat, change.stream.evictedTurns);
    }
  }

  targets() {
    return [...this.#chats.entries()].map(([chatId, chat]) => ({
      chatId, covered: chat.covered, earlier: chat.earlier, partial: chat.partial,
    }));
  }

  recordPage(chatId: string, page: MessageSearchPage) {
    const chat = this.#chats.get(chatId);
    if (!chat) return;
    for (const row of page.rows) if (!chat.rows.has(row.itemId)) this.#upsert(chat, row);
    this.#cover(chat, page.more);
  }

  contains(hit: SearchHit) {
    return this.#chats.get(hit.chatId)?.rows.get(hit.itemId)?.turnId === hit.turnId;
  }

  async find(query: string, signal: AbortSignal): Promise<SearchHit[]> {
    const search = fold(query.trim());
    if (!search) return [];
    const hits: SearchHit[] = [];
    let examined = 0;
    for (const [chatId, chat] of this.#chats) {
      for (const row of chat.rows.values()) {
        if (signal.aborted) return [];
        if (++examined % 128 === 0) {
          await new Promise<void>((resolve) => setTimeout(resolve, 0));
          if (signal.aborted) return [];
        }
        for (const content of row.content) {
          const location = content.folded.indexOf(search);
          if (location < 0) continue;
          hits.push({
            chatId, chatTitle: chat.title, itemId: row.itemId, turnId: row.turnId,
            ...snippet(content.original, location, search.length),
          });
          break;
        }
        if (hits.length === MAX_RESULTS) return hits;
      }
    }
    return hits;
  }

  #syncChats(snapshot: WorkspaceSnapshot) {
    const sidebar = snapshot.navigation.sidebar;
    if (this.#sidebar === sidebar.revision) return;
    this.#sidebar = sidebar.revision;
    const rows = sidebar.chats.filter((row) => row.key.projectId === sidebar.activeProject);
    const members = new Set(rows.map((row) => row.key.chatId));
    for (const [key, chat] of this.#chats) {
      if (!members.has(key)) {
        this.#cost -= chat.cost;
        this.#chats.delete(key);
        this.revision += 1;
      }
    }
    for (const row of rows) {
      const chat = this.#chats.get(row.key.chatId);
      if (!chat) {
        this.#chats.set(row.key.chatId, {
          title: row.title, rows: new Map(), visibleTurns: new Set(),
          covered: false, earlier: false, partial: false, cost: 0,
        });
        this.revision += 1;
      } else if (chat.title !== row.title) {
        chat.title = row.title;
        this.revision += 1;
      }
    }
  }

  #cover(chat: Chat, earlier: boolean) {
    if (!chat.covered || chat.earlier !== earlier) {
      chat.covered = true;
      chat.earlier = earlier;
      this.revision += 1;
    }
  }

  #upsert(chat: Chat, row: TranscriptItem) {
    const original = body(row);
    const prior = chat.rows.get(row.itemId);
    if (prior && prior.turnId === row.turnId &&
        prior.content.length === original.length && prior.content.every((item, index) => item.original === original[index])) return;
    if (prior) this.#remove(chat, prior);
    if (!original.length) return;
    if (original.reduce((size, value) => size + value.length, 96) > MAX_CHAT_COST) {
      this.#partial(chat);
      return;
    }
    const content = original.map((value) => ({ original: value, folded: fold(value) }));
    const cost = content.reduce((sum, item) => sum + item.original.length + item.folded.length, 96);
    if (cost > MAX_CHAT_COST) {
      this.#partial(chat);
      return;
    }
    while (chat.cost + cost > MAX_CHAT_COST) this.#dropFirst(chat);
    while (this.#cost + cost > MAX_INDEX_COST) {
      const available = [...this.#chats.values()].find((item) => item !== chat && item.rows.size) ?? chat;
      this.#dropFirst(available);
    }
    chat.rows.set(row.itemId, { itemId: row.itemId, turnId: row.turnId, content, cost });
    chat.cost += cost;
    this.#cost += cost;
    this.revision += 1;
  }

  #dropFirst(chat: Chat) {
    const first = chat.rows.values().next().value;
    if (first) this.#remove(chat, first);
    this.#partial(chat);
  }

  #remove(chat: Chat, row: Entry) {
    chat.rows.delete(row.itemId);
    this.#cost -= row.cost;
    chat.cost -= row.cost;
    this.revision += 1;
  }

  #partial(chat: Chat) {
    if (chat.partial) return;
    chat.partial = true;
    this.revision += 1;
  }

  #evict(chat: Chat, turns: string[]) {
    if (!turns.length) return;
    const evicted = new Set(turns);
    for (const turn of evicted) chat.visibleTurns.delete(turn);
    for (const row of chat.rows.values()) if (evicted.has(row.turnId)) this.#remove(chat, row);
    this.#partial(chat);
  }
}
