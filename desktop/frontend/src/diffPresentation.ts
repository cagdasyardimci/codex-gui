export type DiffLine = {
  kind: 'add' | 'delete' | 'context' | 'note';
  raw: string;
  before?: number;
  after?: number;
};

export type DiffRun = { lines: DiffLine[]; unchanged: boolean };
export type DiffHunk = { heading: string; runs: DiffRun[] };
export type DiffPair = { before?: DiffLine; after?: DiffLine; note?: DiffLine };

export function parsePatch(text: string): { header: string; hunks: DiffHunk[] } | undefined {
  if (text.length > 512 * 1024) return;
  const rows = text.split('\n');
  if (rows.length > 5000) return;
  const header: string[] = [];
  const hunks: DiffHunk[] = [];
  let hunk: DiffHunk | undefined;
  let before = 0;
  let after = 0;
  for (const raw of rows) {
    const range = /^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/.exec(raw);
    if (range) {
      before = Number(range[1]);
      after = Number(range[2]);
      hunk = { heading: raw, runs: [] };
      hunks.push(hunk);
      continue;
    }
    if (!hunk) {
      header.push(raw);
      continue;
    }
    if (!raw) continue;
    const prefix = raw[0];
    const line: DiffLine = prefix === '+' ? { kind: 'add', raw, after: after++ }
      : prefix === '-' ? { kind: 'delete', raw, before: before++ }
      : prefix === ' ' ? { kind: 'context', raw, before: before++, after: after++ }
      : { kind: 'note', raw };
    const unchanged = line.kind === 'context';
    const run = hunk.runs.at(-1);
    if (run?.unchanged === unchanged) run.lines.push(line);
    else hunk.runs.push({ unchanged, lines: [line] });
  }
  return hunks.length ? { header: header.join('\n'), hunks } : undefined;
}

export function splitRows(lines: DiffLine[]): DiffPair[] {
  const rows: DiffPair[] = [];
  const removed: DiffLine[] = [];
  const added: DiffLine[] = [];
  function flush() {
    for (let index = 0; index < Math.max(removed.length, added.length); index++) {
      rows.push({ before: removed[index], after: added[index] });
    }
    removed.length = 0;
    added.length = 0;
  }
  for (const line of lines) {
    if (line.kind === 'delete') removed.push(line);
    else if (line.kind === 'add') added.push(line);
    else {
      flush();
      rows.push(line.kind === 'note' ? { note: line } : { before: line, after: line });
    }
  }
  flush();
  return rows;
}
