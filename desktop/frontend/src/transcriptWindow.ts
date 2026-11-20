import type { TranscriptItem } from './generated/workspace';

const OVERSCAN = 8;
const ESTIMATED_LINE = 21;
const ESTIMATED_HEADER = 41;
const estimates = new WeakMap<TranscriptItem, number>();

export type TranscriptGeometry = {
  rows: TranscriptItem[];
  offsets: number[];
  positions: Map<string, number>;
  height: number;
};

export type ReadingAnchor = { itemId: string; turnId: string; offset: number };
export type WindowEntry = { key: string; item: TranscriptItem } | { key: string; gap: number };

export function geometry(rows: TranscriptItem[], measured: ReadonlyMap<string, number>): TranscriptGeometry {
  const offsets = [0];
  const positions = new Map<string, number>();
  for (const row of rows) {
    positions.set(row.itemId, offsets.length - 1);
    const size = measured.get(row.itemId) ?? estimate(row);
    offsets.push(offsets[offsets.length - 1]! + size);
  }
  return { rows, offsets, positions, height: offsets[offsets.length - 1]! };
}

function estimate(row: TranscriptItem): number {
  const prior = estimates.get(row);
  if (prior !== undefined) return prior;
  const size = row.role === 'commands' ? 36 : ESTIMATED_HEADER +
    ESTIMATED_LINE * Math.min(240, Math.max(1, Math.ceil(row.text.length / 80), row.text.slice(0, 32_768).split('\n').length));
  estimates.set(row, size);
  return size;
}

function rowAt(layout: TranscriptGeometry, offset: number): number {
  let lower = 0;
  let upper = layout.rows.length;
  while (lower < upper) {
    const middle = Math.floor((lower + upper) / 2);
    if (layout.offsets[middle + 1]! <= offset) lower = middle + 1;
    else upper = middle;
  }
  return Math.min(lower, layout.rows.length - 1);
}

export function readingAnchor(layout: TranscriptGeometry, offset: number): ReadingAnchor | undefined {
  const at = rowAt(layout, offset + 1);
  const row = layout.rows[at];
  if (row) return { itemId: row.itemId, turnId: row.turnId, offset: offset - layout.offsets[at]! };
}

export function restoredOffset(layout: TranscriptGeometry, anchor: ReadingAnchor): number | undefined {
  const at = layout.positions.get(anchor.itemId);
  if (at !== undefined) return layout.offsets[at]! + anchor.offset;
}

export function selectedSpan(layout: TranscriptGeometry, selection: [string, string] | undefined): [number, number] | undefined {
  if (!selection) return;
  const first = layout.positions.get(selection[0]);
  const last = layout.positions.get(selection[1]);
  if (first !== undefined && last !== undefined) return [Math.min(first, last), Math.max(first, last)];
}

export function windowEntries(layout: TranscriptGeometry, top: number, height: number,
  selection: [string, string] | undefined, focused: string | undefined): WindowEntry[] {
  if (!layout.rows.length) return [];
  const from = Math.max(0, rowAt(layout, top) - OVERSCAN);
  const through = Math.min(layout.rows.length - 1, rowAt(layout, top + height) + OVERSCAN);
  const included = new Set<number>();
  for (let index = from; index <= through; index++) included.add(index);
  const selected = selectedSpan(layout, selection);
  if (selected) for (let index = selected[0]; index <= selected[1]; index++) included.add(index);
  const focusIndex = focused === undefined ? undefined : layout.positions.get(focused);
  if (focusIndex !== undefined) included.add(focusIndex);
  let previous = 0;
  const entries: WindowEntry[] = [];
  for (const index of [...included].sort((a, b) => a - b)) {
    const item = layout.rows[index]!;
    if (index > previous) entries.push({ key: `gap:${item.itemId}`, gap: layout.offsets[index]! - layout.offsets[previous]! });
    entries.push({ key: `row:${item.itemId}`, item });
    previous = index + 1;
  }
  if (previous < layout.rows.length) entries.push({ key: 'gap:end', gap: layout.height - layout.offsets[previous]! });
  return entries;
}

export function protectedTurns(layout: TranscriptGeometry, top: number, height: number,
  selection: [string, string] | undefined, focused: string | undefined): string[] {
  const result = new Set<string>();
  const include = (start: number, end: number) => {
    for (let at = start; at <= end; at++) {
      const row = layout.rows[at];
      if (row?.turnId) result.add(row.turnId);
    }
  };
  if (layout.rows.length) include(rowAt(layout, top), rowAt(layout, top + height));
  const selected = selectedSpan(layout, selection);
  if (selected) include(selected[0], selected[1]);
  const focusIndex = focused === undefined ? undefined : layout.positions.get(focused);
  if (focusIndex !== undefined) include(focusIndex, focusIndex);
  return [...result];
}
