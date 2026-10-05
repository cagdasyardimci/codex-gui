#!/usr/bin/env python3
"""Synthetic app-server for native UI checks. No model calls or project writes.

Launch a QA bundle with CODEX_EXECUTABLE pointing at this script. Optionally set
CODEX_GUI_QA_STATE to a temporary JSON file to persist rename/archive choices.

Include [qa-late-command-after-stop] in a task-control turn to retain its approved
synthetic command after Stop. qaLateCommandDelaySeconds in the QA state controls
the late-event delay (default 3 seconds, bounded to 0.25–10 seconds).
"""
import fcntl
import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import time
import uuid

if '--version' in sys.argv:
    print('codex-cli 0.153.2')
    sys.exit(0)

state_path = os.environ.get('CODEX_GUI_QA_STATE')
trace_path = os.environ.get('CODEX_GUI_QA_TRACE')
state = json.loads(Path(state_path).read_text()) if state_path and Path(state_path).exists() else {}
lock = threading.Lock()
history_lock = threading.Lock()
turn_counter = 0
streamed_turns = {}
active_turns = {}
approval_events = {}
approval_decisions = {}
threads = state.setdefault('threads', [
    {'id': 'qa-reading', 'name': 'Markdown and streaming', 'preview': 'Native reading fixture', 'archived': False},
    {'id': 'qa-navigation', 'name': 'Find rename and archive', 'preview': 'Navigation acceptance fixture', 'archived': False},
    {'id': 'qa-task-control', 'name': 'Active task ownership', 'preview': 'Synthetic task-control fixture', 'archived': False},
    {'id': 'qa-review', 'name': 'Review and validation', 'preview': 'Synthetic multi-turn review fixture', 'archived': False},
    {'id': 'qa-context', 'name': 'Project context and history', 'preview': 'Synthetic reuse and search fixture', 'archived': False},
    {'id': 'qa-activity', 'name': 'Activity groups and details', 'preview': 'Read, search, command, image, and timing fixture', 'archived': False},
])
markdown = r'''Return the Markdown below exactly. Preserve its line breaks, indentation, punctuation, and code fences. Do not add commentary or wrap the entire response in a code fence.

# Markdown Rendering Test

START_MARKER

## 1. Inline formatting and Unicode

Plain text, **bold**, *italic*, ***bold italic***, ~~strikethrough~~, and `inline_code`.

Unicode before styled text: 👩🏽‍💻 café é Türkçe 日本語 — **UNICODE_BOLD_MARKER** and `UNICODE_CODE_MARKER`.

A [documentation link](https://developer.apple.com/documentation/appkit) and a [reference link][appkit].

Inline code must remain literal: `**not bold** <tag> & []()`.

## 2. Paragraphs and line breaks

This is a soft line break.
This should continue the same paragraph.

This is a forced hard break.\
This should start a new line without a paragraph-sized gap.

This is a separate paragraph.

## 3. Lists

- First bullet contains enough words to wrap when the conversation is narrow. Its continuation should align with the text.
- Second bullet
  - Nested bullet
    - Third-level bullet with **bold text**
  - Another nested bullet

3. Numbered list starting at three
4. Another numbered item
   1. Nested numbered item
   2. Another nested item

- [x] Completed task
- [ ] Pending task
  - [x] Nested completed task

## 4. Block quotes

> A quoted paragraph with **bold**, *italic*, and a [link](https://example.com).
>
> A second quoted paragraph.
>
> - First quoted list item
> - Second quoted list item
>
> > A nested quotation.

## 5. Tables

| Left aligned | Center aligned | Right aligned |
| :--- | :---: | ---: |
| A longer cell should wrap naturally across several words when the window is narrow. | **Center bold** | 12.50 |
| [AppKit](https://developer.apple.com/documentation/appkit) | `table_code` | 1234 |
| 👩🏽‍💻 café é 日本語 | ~~obsolete~~ | 7 |
| Escaped pipe: A \| B | *Center italic* | -42 |

TABLE_END_MARKER — this paragraph must remain visible below the table.

## 6. Code blocks and copying

Unicode before the first code block: 👩🏽‍💻 café é 日本語.

```python
def greet(name):
    return f"Hello, {name}!"

print(greet("Türkçe 👩🏽‍💻 日本語"))
literal = "* [] < > & ` ** not Markdown"
```

```swift
let message = "Second block"
print(message)
let unicode = "café é 👩🏽‍💻 日本語"
```

### Heading immediately after code

The two code blocks should remain visually separate, and each copy control should belong to its own block.

Indented code:

    first line
        indented second line

    final line

CODE_END_MARKER

## 7. Escaping and separators

\*Literal asterisks\* and \_literal underscores\_.

Entities: &amp; &lt; &gt; &quot;.

---

Text after the horizontal rule.

## 8. Additional capability probes

Raw HTML: <span>HTML_PROBE</span>

Inline math: $E = mc^2$

Display math:

$$
\int_0^1 x^2\,dx = \frac{1}{3}
$$

```mermaid
flowchart LR
    A[Markdown source] --> B[Parser]
    B --> C[Rendered content]
```

## Final heading

FINAL_MARKER — this must remain readable after resizing, selecting text, and copying code.

[appkit]: https://developer.apple.com/documentation/appkit
'''

markdown_native_edges = '''## Native layout edge probes

> First quoted paragraph has enough words to wrap when the user bubble or conversation pane is narrow.
>
> A second quoted paragraph should share the same continuous outer quote rail.
>
> > A nested quotation remains inside the outer quote.

```swift
let longLine = "CODE_WRAP_MARKER — a long literal line with spaces, Unicode 👩🏽‍💻 café é 日本語, and punctuation * [] < > & that must remain inside its native code card."
```

```text
```

EMPTY_FENCE_END_MARKER — an empty fence must not hide this following paragraph.
'''

# Each chunk leaves representative incomplete syntax until the next arrives.
# The normal interval is two seconds so native observation can inspect each phase.
markdown_stream_chunks = [
    '# Streamed Markdown\n\nSTREAM_START_MARKER — Unicode 👩🏽‍💻 café é 日本語.\n\n',
    'A partial **bo',
    'ld** range and an incomplete [documentation',
    ' link](https://developer.apple.com/documentation/appkit).\n\n',
    'A partial ~~strike',
    'through~~ range with ***bold italic*** text.\n\n',
    '- [x] Completed streamed task\n- [ ] Pending streamed task\n',
    '  - Nested streamed bullet\n\n> Streamed quotation with **bold** text.\n\n',
    '| Left | Center | Right |\n',
    '| :--- | :---: | ---: |\n',
    '| A streamed cell wraps at narrow widths. | `table_code` | 42 |\n\n',
    '```swi',
    'ft\nlet message = "Streamed 👩🏽‍💻 café é 日本語"\n',
    'let separators = "line\u2028paragraph\u2029end"\nprint(message)\n',
    '```\n\n---\n\n',
    'STREAM_END_MARKER — all chunks must remain visible without duplication.\n',
]


def send(message):
    with lock:
        print(json.dumps(message), flush=True)


def save(changed_thread=None):
    """Merge one owner's edit under a process-shared lock and publish atomically."""
    if not state_path:
        return
    path = Path(state_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.with_suffix(path.suffix + '.lock').open('a') as guard:
        fcntl.flock(guard, fcntl.LOCK_EX)
        latest = json.loads(path.read_text()) if path.exists() else dict(state)
        by_id = {thread['id']: thread for thread in latest.get('threads', [])}
        for thread in threads:
            by_id.setdefault(thread['id'], dict(thread))
        if changed_thread is not None:
            by_id[changed_thread['id']] = dict(changed_thread)
        latest['threads'] = list(by_id.values())
        if 'cwd' in state:
            latest.setdefault('cwd', state['cwd'])
        with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as output:
            json.dump(latest, output)
            temporary_path = Path(output.name)
        try:
            os.replace(temporary_path, path)
        finally:
            temporary_path.unlink(missing_ok=True)
        state.update(latest)
        threads[:] = latest['threads']


def refresh_saved_threads():
    """Atomic writes let a client read other owners' saved conversations safely."""
    if state_path and Path(state_path).exists():
        latest = json.loads(Path(state_path).read_text())
        state.update(latest)
        threads[:] = latest.get('threads', threads)


def trace(entry):
    """Append request evidence only when explicitly pointed at a temporary trace file."""
    if trace_path:
        path = Path(trace_path)
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open('a') as output:
            output.write(json.dumps(entry, sort_keys=True) + '\n')


def summary(t):
    with history_lock:
        active = active_turns.get(t['id'])
        status = {'type': 'idle'}
        if active:
            flags = ['waitingOnApproval'] if active.get('waitingOnApproval') else []
            status = {'type': 'active', 'activeFlags': flags}
    public = {key: value for key, value in t.items() if key not in ('fixtureTurns', 'settings')}
    return {**public, 'cwd': t.get('cwd', state.get('cwd', os.getcwd())),
            'status': status, 'turns': []}


def thread_for_id(thread_id):
    return next((thread for thread in threads if thread['id'] == thread_id), None)


def thread_cwd(thread_id):
    thread = thread_for_id(thread_id)
    return thread.get('cwd', state.get('cwd', os.getcwd())) if thread else os.getcwd()


def bind_legacy_threads(cwd):
    """Place the built-in fixtures in the first project listed by an older QA state."""
    for thread in threads:
        thread.setdefault('cwd', cwd)


def thread_settings(thread):
    """Return the app-server's effective settings, separate from the thread summary."""
    models = state.get('models', ['gpt-6-astra', 'gpt-5.6-luna'])
    return {
        'model': models[0], 'modelProvider': 'openai',
        'cwd': thread_cwd(thread['id']), 'reasoningEffort': 'medium',
        'serviceTier': None, 'collaborationMode': {
            'mode': 'default', 'settings': {'model': models[0], 'reasoning_effort': 'medium',
                                           'developer_instructions': None}},
        'approvalPolicy': 'on-request', 'approvalsReviewer': 'user',
        'sandboxPolicy': {'type': 'workspaceWrite', 'writableRoots': [thread_cwd(thread['id'])],
                          'networkAccess': False, 'excludeTmpdirEnvVar': False,
                          'excludeSlashTmp': False},
        **thread.get('settings', {}),
    }


def valid_collaboration_mode(value):
    if not isinstance(value, dict) or value.get('mode') not in ('plan', 'default'):
        return False
    settings = value.get('settings')
    if not isinstance(settings, dict) or settings.get('model') not in state.get(
            'models', ['gpt-6-astra', 'gpt-5.6-luna']):
        return False
    return ('reasoning_effort' in settings and
            (settings['reasoning_effort'] is None or
             settings['reasoning_effort'] in ('low', 'medium', 'high')) and
            'developer_instructions' in settings and
            (settings['developer_instructions'] is None or
             isinstance(settings['developer_instructions'], str)))


def thread_response(thread):
    settings = thread_settings(thread)
    # Read/start/resume/fork cannot verify collaboration mode; only the settings event can.
    settings.pop('collaborationMode')
    settings['sandbox'] = settings.pop('sandboxPolicy')
    return {'thread': summary(thread), **settings}


def token_usage():
    last = {'inputTokens': 1200, 'cachedInputTokens': 400, 'cacheWriteInputTokens': 0,
            'outputTokens': 80, 'reasoningOutputTokens': 20, 'totalTokens': 1280}
    total = {key: value * 2 for key, value in last.items()}
    return {'last': last, 'total': total, 'modelContextWindow': 128000}


def history(thread_id, cursor=None):
    cwd = thread_cwd(thread_id)
    thread = thread_for_id(thread_id)
    if thread and 'fixtureTurns' in thread:
        with history_lock:
            copied = json.loads(json.dumps(thread['fixtureTurns']))
            saved_turns = json.loads(json.dumps(streamed_turns.get(thread_id, [])))
        return copied + saved_turns, None
    if thread_id == 'qa-activity':
        with history_lock:
            saved_turns = json.loads(json.dumps(streamed_turns.get(thread_id, [])))
        return [activity_history(cwd)] + saved_turns, None
    items = [{'id': f'message-{i}', 'type': 'agentMessage',
              'text': f'## Earlier message {i}\n\n' + 'Readable conversation history. ' * 8} for i in range(160)]
    items += [{'id': 'long-command', 'type': 'commandExecution', 'status': 'completed',
               'command': 'synthetic-output', 'exitCode': 0,
               'aggregatedOutput': ''.join(f'OUTPUT_{i:04d}: literal * [] < > & \\n\n' for i in range(1000))},
              {'id': 'rich-message', 'type': 'agentMessage', 'text': markdown}]
    if thread_id == 'qa-reading':
        # Same source in both roles isolates presentation from protocol content.
        items.insert(-1, {'id': 'rich-user-message', 'type': 'userMessage',
                          'content': [{'type': 'text', 'text': markdown}]})
        items += [
            {'id': 'native-edge-user-message', 'type': 'userMessage',
             'content': [{'type': 'text', 'text': markdown_native_edges}]},
            {'id': 'native-edge-message', 'type': 'agentMessage',
             'text': markdown_native_edges},
        ]
    if thread_id == 'qa-navigation':
        items = [{'id': 'navigation-message', 'type': 'agentMessage', 'text': 'Conversation management fixture.'},
                 {'id': 'qa-change', 'type': 'fileChange', 'status': 'completed',
                  'changes': [{'path': 'file with spaces.swift', 'kind': {'type': 'update'},
                               'diff': '@@ -3 +3 @@\n-print("Old")\n+print(greeting)\n'}]}]
    elif thread_id == 'qa-task-control':
        items = [{'id': 'task-control-message', 'type': 'agentMessage',
                  'text': 'Synthetic task-control fixture. Start a turn to inspect plan, activity, approval, steering, and thread ownership.'}]
    elif thread_id == 'qa-review':
        items = []
        turns = [
            {'id': 'qa-review-turn-1', 'status': 'completed', 'items': [
                {'id': 'qa-review-request-1', 'type': 'userMessage',
                 'content': [{'type': 'text', 'text': 'Refactor the parser and add deterministic validation output.'}]},
                {'id': 'qa-review-answer-1', 'type': 'agentMessage',
                 'text': 'Parser refactor complete. Review each changed file and validation result.'},
                {'id': 'qa-review-files-1', 'type': 'fileChange', 'status': 'completed', 'changes': [
                    {'path': 'Sources/OldParser.swift', 'kind': {'type': 'update', 'move_path': 'Sources/Parser.swift'},
                     'diff': '@@ -1,2 +1,3 @@\n-import OldParser\n+import ParserCore\n+// rename review hunk\n'},
                    {'path': 'Sources/RemovedAdapter.swift', 'kind': {'type': 'delete'},
                     'diff': '@@ -1,2 +0,0 @@\n-struct RemovedAdapter {}\n-// deleted adapter\n'},
                    {'path': 'Fixtures/sample.bin', 'kind': {'type': 'update'},
                     'diff': 'Binary files a/Fixtures/sample.bin and b/Fixtures/sample.bin differ\n'},
                    {'path': 'Sources/LongLine.swift', 'kind': {'type': 'update'},
                     'diff': '@@ -8 +8 @@\n-let old = 1\n+let result = ' + ('veryLongValue' * 18) + '\n'},
                ]},
                {'id': 'qa-review-test-pass', 'type': 'commandExecution', 'status': 'completed',
                 'command': 'swift test --filter ParserTests', 'cwd': cwd,
                 'aggregatedOutput': 'Executed 12 tests; 0 failures.', 'exitCode': 0},
                {'id': 'qa-review-test-fail', 'type': 'commandExecution', 'status': 'failed',
                 'command': 'swift test --filter AdapterTests', 'cwd': cwd,
                 'aggregatedOutput': 'error: missing expected adapter fixture', 'exitCode': 1},
                {'id': 'qa-review-test-unknown', 'type': 'commandExecution', 'status': 'completed',
                 'command': 'swift test --filter IntegrationTests', 'cwd': cwd,
                 'aggregatedOutput': 'Process completed without an exit code in this fixture.'},
            ]},
            {'id': 'qa-review-turn-2', 'status': 'completed', 'items': [
                {'id': 'qa-review-request-2', 'type': 'userMessage',
                 'content': [{'type': 'text', 'text': 'Adjust the parser edge case.'}]},
                {'id': 'qa-review-files-2', 'type': 'fileChange', 'status': 'completed', 'changes': [
                    {'path': 'Sources/Parser.swift', 'kind': {'type': 'update'},
                     'diff': '@@ -2 +2 @@\n-let mode = .strict\n+let mode = .compatible\n'},
                ]},
            ]},
        ]
        with history_lock:
            saved_turns = json.loads(json.dumps(streamed_turns.get(thread_id, [])))
        return list(reversed(turns)) + saved_turns, None
    elif thread_id == 'qa-context':
        turns = [
            {'id': 'qa-context-turn-old', 'status': 'completed', 'items': [
                {'id': 'qa-context-old-request', 'type': 'userMessage',
                 'content': [{'type': 'text', 'text': 'Why preserve the parser API?'}]},
                {'id': 'qa-context-decision', 'type': 'agentMessage',
                 'text': 'Decision: keep the parser API source-compatible; see the migration note.'},
            ]},
            {'id': 'qa-context-turn-failure', 'status': 'completed', 'items': [
                {'id': 'qa-context-failure-request', 'type': 'userMessage',
                 'content': [{'type': 'text', 'text': 'Run parser tests.'}]},
                {'id': 'qa-context-failure', 'type': 'commandExecution', 'status': 'failed',
                 'command': 'swift test --filter ParserTests', 'cwd': cwd,
                 'aggregatedOutput': 'Synthetic failure: missing parser fixture.', 'exitCode': 1},
                {'id': 'qa-context-change', 'type': 'fileChange', 'status': 'completed', 'changes': [
                    {'path': 'Sources/Parser.swift', 'kind': {'type': 'update'},
                     'diff': '@@ -4 +4 @@\n-let mode = .strict\n+let mode = .compatible\n'},
                ]},
            ]},
            {'id': 'qa-context-turn-current', 'status': 'completed', 'items': [
                {'id': 'qa-context-current-request', 'type': 'userMessage',
                 'content': [{'type': 'text', 'text': 'Find the earlier compatibility decision.'}]},
                {'id': 'qa-context-current-answer', 'type': 'agentMessage',
                 'text': 'The earlier decision keeps the parser API source-compatible.'},
            ]},
        ]
        if cursor == 'qa-context-older':
            return turns[:1], None
        return turns[1:], 'qa-context-older'
    with history_lock:
        saved_turns = json.loads(json.dumps(streamed_turns.get(thread_id, [])))
    turns = [{'id': f'{thread_id}-history', 'status': 'completed', 'items': items}] + saved_turns
    # The app-server wire page is newest first; AppServer reverses it for presentation.
    if thread_id == 'qa-reading':
        turns.reverse()
    return turns, None


def activity_history(cwd):
    """Representative activity metadata; the displayed commands are never executed."""
    read_command = "sed -n '1,3p' 'file with spaces.swift'"
    search_command = "rg -n greeting 'file with spaces.swift'"
    return {
        'id': 'qa-activity-history', 'status': 'completed',
        'startedAt': 1790848800, 'completedAt': 1790848924, 'durationMs': 124000,
        'items': [
            {'id': 'activity-request', 'type': 'userMessage',
             'content': [{'type': 'text', 'text': 'Inspect the fixture and show the activity details.'}]},
            {'id': 'activity-commentary', 'type': 'agentMessage',
             'text': 'I will inspect the file, search its contents, and show command details.'},
            *[{'id': f'activity-read-{index}', 'type': 'commandExecution',
               'command': read_command, 'cwd': cwd, 'status': 'completed', 'exitCode': 0,
               'commandActions': [{'type': 'read', 'command': read_command,
                                   'name': 'file with spaces.swift', 'path': 'file with spaces.swift'}],
               'aggregatedOutput': '// Native editor handoff fixture\nlet greeting = "Hello"\nprint(greeting)\n',
               'durationMs': 12} for index in range(2)],
            {'id': 'activity-search', 'type': 'commandExecution',
             'command': search_command, 'cwd': cwd, 'status': 'completed', 'exitCode': 0,
             'commandActions': [{'type': 'search', 'command': search_command,
                                 'query': 'greeting', 'path': 'file with spaces.swift'}],
             'aggregatedOutput': '2:let greeting = "Hello"\n3:print(greeting)\n'},
            {'id': 'activity-shell', 'type': 'commandExecution',
             'command': "python3 - <<'PY'\nprint('Synthetic output; no Python command ran.')\nPY",
             'cwd': cwd, 'status': 'completed', 'exitCode': 0, 'durationMs': 1800,
             'commandActions': [{'type': 'unknown', 'command': 'python3 - synthetic fixture'}],
             'aggregatedOutput': ''.join(f'ACTIVITY_OUTPUT_{index:03d}: literal * [] < > &\n' for index in range(80))},
            {'id': 'activity-next-commentary', 'type': 'agentMessage',
             'text': 'The two reads remain separate. This next command reports a failure.'},
            {'id': 'activity-failure', 'type': 'commandExecution',
             'command': 'synthetic-check --fixture', 'cwd': cwd, 'status': 'completed',
             'aggregatedOutput': 'Synthetic validation failure; no command ran.\n', 'exitCode': 2},
            {'id': 'activity-image', 'type': 'imageView', 'path': str(Path(cwd) / 'activity-preview.png')},
            {'id': 'activity-answer', 'type': 'agentMessage',
             'text': 'Activity fixture complete. Expand groups and individual commands independently.'},
        ],
    }


def run_activity_turn(thread_id, turn_id, item_id, stop_event, cwd):
    """Stream command output and timestamps without invoking a model or subprocess."""
    started = time.time()
    item = {'id': item_id, 'type': 'agentMessage',
            'text': 'Streaming synthetic command output for the activity presentation check.'}
    command = {'id': f'activity-stream-{turn_id}', 'type': 'commandExecution',
               'command': 'synthetic-stream --lines 30', 'cwd': cwd,
               'status': 'inProgress', 'aggregatedOutput': '',
               'commandActions': [{'type': 'unknown', 'command': 'synthetic-stream --lines 30'}]}
    turn = {'id': turn_id, 'status': 'inProgress', 'startedAt': int(started),
            'items': [dict(item), dict(command)]}
    with history_lock:
        streamed_turns.setdefault(thread_id, []).append(turn)
        active_turns[thread_id] = {
            'turnId': turn_id, 'turn': turn, 'item': item, 'stopEvent': stop_event,
        }
    send({'method': 'turn/started', 'params': {'threadId': thread_id, 'turn': turn}})
    for value in (item, command):
        send({'method': 'item/started', 'params': {
            'threadId': thread_id, 'turnId': turn_id, 'item': value}})
    send({'method': 'item/completed', 'params': {
        'threadId': thread_id, 'turnId': turn_id, 'item': item}})
    for index in range(30):
        if stop_event.wait(0.3):
            break
        delta = f'LIVE_ACTIVITY_{index:02d}: synthetic output\n'
        with history_lock:
            command['aggregatedOutput'] += delta
            turn['items'] = [dict(item), dict(command)]
        send({'method': 'item/commandExecution/outputDelta', 'params': {
            'threadId': thread_id, 'turnId': turn_id, 'itemId': command['id'], 'delta': delta}})
    ended = time.time()
    with history_lock:
        command['status'] = 'completed'
        command['exitCode'] = 0
        command['durationMs'] = round((ended - started) * 1000)
        turn.update(status='interrupted' if stop_event.is_set() else 'completed',
                    completedAt=int(ended), durationMs=command['durationMs'],
                    items=[dict(item), dict(command)])
        active_turns.pop(thread_id, None)
    send({'method': 'item/completed', 'params': {
        'threadId': thread_id, 'turnId': turn_id, 'item': command}})
    send({'method': 'turn/completed', 'params': {'threadId': thread_id, 'turn': turn}})


def next_turn_id(thread_id):
    global turn_counter
    with history_lock:
        turn_counter += 1
        return f'qa-{thread_id}-turn-{turn_counter}', f'stream-message-{turn_counter}'


def command_turn(thread_id, item_types):
    turn_id, item_id = next_turn_id(thread_id)
    items = [{'id': f'{item_id}-{index}', 'type': kind}
             for index, kind in enumerate(item_types)]
    for item in items:
        if item['type'] in ('enteredReviewMode', 'exitedReviewMode'):
            item['review'] = 'Synthetic review of the requested target.'
        elif item['type'] == 'agentMessage':
            item['text'] = 'Synthetic review complete; no model or project write occurred.'
    turn = {'id': turn_id, 'status': 'inProgress', 'items': [], 'error': None}
    stop_event = threading.Event()
    with history_lock:
        streamed_turns.setdefault(thread_id, []).append(turn)
        active_turns[thread_id] = {
            'turnId': turn_id, 'turn': turn, 'item': items[0], 'stopEvent': stop_event,
        }
    return turn, items, stop_event


def begin_command_turn(thread_id, turn, items):
    send({'method': 'turn/started', 'params': {'threadId': thread_id, 'turn': turn}})
    send({'method': 'thread/status/changed', 'params': {
        'threadId': thread_id, 'status': {'type': 'active', 'activeFlags': []}}})
    send({'method': 'item/started', 'params': {
        'threadId': thread_id, 'turnId': turn['id'], 'item': items[0]}})


def finish_command_turn(thread_id, turn, items, stop_event, already_started=False):
    # Compact must acknowledge first; review deliberately sends its first events before the reply.
    time.sleep(0.05)
    if not already_started:
        begin_command_turn(thread_id, turn, items)
    for index, item in enumerate(items):
        if index:
            send({'method': 'item/started', 'params': {
                'threadId': thread_id, 'turnId': turn['id'], 'item': item}})
        send({'method': 'item/completed', 'params': {
            'threadId': thread_id, 'turnId': turn['id'], 'item': item}})
    send({'method': 'thread/tokenUsage/updated', 'params': {
        'threadId': thread_id, 'turnId': turn['id'], 'tokenUsage': token_usage()}})
    with history_lock:
        turn['items'] = json.loads(json.dumps(items))
        turn['status'] = 'interrupted' if stop_event.is_set() else 'completed'
        active_turns.pop(thread_id, None)
    send({'method': 'turn/completed', 'params': {'threadId': thread_id, 'turn': turn}})
    send({'method': 'thread/status/changed', 'params': {
        'threadId': thread_id, 'status': {'type': 'idle'}}})


def finish_late_command_after_stop(thread_id, turn, item, command_item, stop_event, cwd):
    """Simulate command lifetime beyond interruption; no subprocess is executed."""
    stop_event.wait(240)
    with history_lock:
        turn['status'] = 'interrupted' if stop_event.is_set() else 'completed'
        turn['items'] = [dict(item), dict(command_item)]
        active_turns.pop(thread_id, None)
    send({'method': 'turn/completed', 'params': {'threadId': thread_id, 'turn': turn}})
    trace({'method': 'qa/late-command/turnCompleted', 'threadId': thread_id,
           'turnId': turn['id'], 'itemId': command_item['id'], 'cwd': cwd,
           'status': turn['status'], 'commandStatus': command_item['status']})

    delay = max(0.25, min(10.0, float(state.get('qaLateCommandDelaySeconds', 3.0))))
    time.sleep(delay)
    output = 'Synthetic late command finished; no command ran.'
    send({'method': 'item/commandExecution/outputDelta', 'params': {
        'threadId': thread_id, 'turnId': turn['id'], 'itemId': command_item['id'],
        'delta': output,
    }})
    completed_command = {**command_item, 'status': 'completed',
                         'aggregatedOutput': output, 'exitCode': 0}
    with history_lock:
        turn['items'] = [dict(item), completed_command]
    send({'method': 'item/completed', 'params': {
        'threadId': thread_id, 'turnId': turn['id'], 'item': completed_command,
    }})
    trace({'method': 'qa/late-command/itemCompleted', 'threadId': thread_id,
           'turnId': turn['id'], 'itemId': command_item['id'], 'cwd': cwd,
           'status': completed_command['status'], 'delaySeconds': delay})


def run_turn(thread_id, turn_id, item_id, stop_event, cwd, late_command_after_stop=False):
    if thread_id == 'qa-activity':
        run_activity_turn(thread_id, turn_id, item_id, stop_event, cwd)
        return
    is_task_control = thread_id.startswith(('qa-task-control', 'qa-created-'))
    item = {'id': item_id, 'type': 'agentMessage', 'text': ''}
    turn = {'id': turn_id, 'status': 'inProgress', 'items': [item]}
    with history_lock:
        streamed_turns.setdefault(thread_id, []).append(turn)
        active_turns[thread_id] = {
            'turnId': turn_id, 'turn': turn, 'item': item, 'stopEvent': stop_event,
        }
    send({'method': 'turn/started', 'params': {'threadId': thread_id, 'turn': turn}})
    send({'method': 'item/started', 'params': {'threadId': thread_id, 'turnId': turn['id'], 'item': item}})

    if is_task_control:
        send({'method': 'turn/plan/updated', 'params': {
            'threadId': thread_id, 'turnId': turn_id,
            'explanation': 'Synthetic plan for native task ownership checks.',
            'plan': [
                {'step': 'Inspect the fixture', 'status': 'completed'},
                {'step': 'Apply the requested change', 'status': 'inProgress'},
                {'step': 'Review the result', 'status': 'pending'},
            ],
        }})
        send({'method': 'item/mcpToolCall/progress', 'params': {
            'threadId': thread_id, 'turnId': turn_id, 'itemId': item_id,
            'message': 'Synthetic inspection activity',
        }})
        time.sleep(0.5)
        command_item = {
            'id': f'qa-command-{turn_id}', 'type': 'commandExecution',
            'command': 'printf synthetic-approval', 'cwd': cwd,
            'status': 'inProgress', 'aggregatedOutput': '',
        }
        send({'method': 'item/started', 'params': {
            'threadId': thread_id, 'turnId': turn_id, 'item': command_item,
        }})
        changes = [{
            'path': 'file with spaces.swift', 'kind': {'type': 'update'},
            'diff': '@@ -3 +3 @@\n-print("Old")\n+print("Synthetic task-control change")\n',
        }]
        send({'method': 'item/fileChange/patchUpdated', 'params': {
            'threadId': thread_id, 'turnId': turn_id,
            'itemId': f'qa-file-change-{turn_id}', 'changes': changes,
        }})
        send({'method': 'turn/diff/updated', 'params': {
            'threadId': thread_id, 'turnId': turn_id,
            'diff': changes[0]['diff'],
        }})
        with lock:
            approval_id = f'qa-approval-{turn_id}'
            approval_event = threading.Event()
            approval_events[approval_id] = approval_event
        with history_lock:
            active_turns[thread_id]['waitingOnApproval'] = True
        send({
            'id': approval_id,
            'method': 'item/commandExecution/requestApproval',
            'params': {
                'threadId': thread_id, 'turnId': turn_id, 'itemId': command_item['id'],
                'reason': 'Synthetic approval fixture; no command will run.',
                'command': 'printf synthetic-approval', 'cwd': cwd,
                'approvalId': f'qa-callback-{turn_id}',
                'availableDecisions': ['accept', 'decline', 'cancel'],
            },
        })
        # The main input loop remains available while the owner decides or stops the task.
        approval_deadline = time.monotonic() + 240
        while not approval_event.wait(0.25):
            if stop_event.is_set() or time.monotonic() >= approval_deadline:
                break
        send({'method': 'serverRequest/resolved', 'params': {
            'threadId': thread_id, 'requestId': approval_id,
        }})
        with lock:
            approval_events.pop(approval_id, None)
            decision = approval_decisions.pop(approval_id, None)
        with history_lock:
            active = active_turns.get(thread_id)
            if active and active['turnId'] == turn_id:
                active['waitingOnApproval'] = False
        if late_command_after_stop and decision == 'accept':
            finish_late_command_after_stop(thread_id, turn, item, command_item, stop_event, cwd)
            return
        command_item['status'] = 'completed'
        command_item['aggregatedOutput'] = 'Synthetic approval recorded; no command ran.'
        send({'method': 'item/completed', 'params': {
            'threadId': thread_id, 'turnId': turn_id, 'item': command_item,
        }})

    stream_count = 240 if is_task_control else 160
    stream_interval = 1.0 if is_task_control else 0.2
    deltas = [f'\n- Streamed line {i}: readable output while browsing earlier messages.'
              for i in range(stream_count)]
    if thread_id == 'qa-reading':
        deltas = markdown_stream_chunks
        stream_interval = max(0.01, min(5.0, float(state.get('qaMarkdownStreamIntervalSeconds', 2.0))))
    for delta in deltas:
        if stop_event.wait(stream_interval):
            break
        with history_lock:
            item['text'] += delta
            turn['items'] = [dict(item)]
        send({'method': 'item/agentMessage/delta', 'params': {'threadId': thread_id, 'turnId': turn['id'], 'itemId': item['id'], 'delta': delta}})
    with history_lock:
        turn['status'] = 'interrupted' if stop_event.is_set() else 'completed'
        turn['items'] = [dict(item)]
    send({'method': 'item/completed', 'params': {'threadId': thread_id, 'turnId': turn['id'], 'item': item}})
    send({'method': 'thread/tokenUsage/updated', 'params': {
        'threadId': thread_id, 'turnId': turn['id'], 'tokenUsage': token_usage()}})
    send({'method': 'turn/completed', 'params': {'threadId': thread_id, 'turn': turn}})
    with history_lock:
        active_turns.pop(thread_id, None)


for line in sys.stdin:
    request = json.loads(line)
    method, params = request.get('method'), request.get('params', {})
    # Responses to synthetic server requests use the same input stream as RPC calls.
    if 'method' not in request and 'id' in request:
        with lock:
            approval_event = approval_events.get(str(request['id']))
            if approval_event:
                approval_decisions[str(request['id'])] = request.get('result', {}).get('decision')
        if approval_event:
            approval_event.set()
        continue
    if 'id' not in request:
        continue
    if method in ('thread/fork', 'thread/compact/start', 'review/start', 'thread/settings/update'):
        refresh_saved_threads()
        t = thread_for_id(params.get('threadId'))
        if t is None:
            send({'id': request['id'], 'error': {
                'code': -32001, 'message': 'Synthetic conversation does not exist.'}})
            continue
        with history_lock:
            busy = t['id'] in active_turns
        if busy:
            send({'id': request['id'], 'error': {
                'code': -32002, 'message': 'Synthetic conversation has an active turn.'}})
            continue
    if method == 'initialize':
        result = {}
    elif method == 'account/read':
        result = {'account': None, 'requiresOpenaiAuth': False}
    elif method == 'skills/list':
        cwd = (params.get('cwds') or [state.get('cwd', os.getcwd())])[0]
        if state.get('qaVariant') == 'unavailable':
            result = {'data': [{'cwd': cwd, 'skills': [], 'errors': [
                {'path': os.path.join(cwd, '.codex', 'skills'), 'message': 'Synthetic discovery unavailable.'}
            ]}]}
        else:
            result = {'data': [{'cwd': cwd, 'skills': [
                {'name': 'qa-review', 'description': 'Synthetic review checklist.',
                 'path': '/tmp/codex-gui-qa/skills/qa-review/SKILL.md', 'scope': 'repo',
                 'enabled': True, 'pluginId': None,
                 'interface': {'displayName': 'QA Review', 'shortDescription': 'Synthetic review skill',
                               'defaultPrompt': 'Review the reported fixture changes.',
                               'iconSmallUrl': None, 'iconLargeUrl': None}},
                {'name': 'qa-disabled', 'description': 'Unavailable synthetic skill.',
                 'path': '/tmp/codex-gui-qa/skills/qa-disabled/SKILL.md', 'scope': 'repo',
                 'enabled': False, 'pluginId': None},
            ], 'errors': [{'path': '/tmp/codex-gui-qa/skills/partial',
                           'message': 'Synthetic partial discovery warning.'}]}]}
    elif method == 'account/rateLimits/read':
        if state.get('qaVariant') == 'unavailable':
            send({'id': request['id'], 'error': {'code': -32010, 'message': 'Synthetic usage unavailable.'}})
            continue
        result = {'rateLimits': {
            'limitId': 'synthetic-primary', 'limitName': 'Synthetic usage window',
            'primary': {'usedPercent': 34, 'resetsAt': 1893456000,
                        'windowDurationMins': 300},
            'secondary': None, 'credits': None, 'individualLimit': None,
            'spendControlReached': False, 'planType': 'synthetic', 'rateLimitReachedType': None,
        }, 'rateLimitsByLimitId': None,
           'rateLimitResetCredits': {'availableCount': 1, 'credits': [
               {'id': 'synthetic-reset-credit', 'resetType': 'primary', 'status': 'available',
                'grantedAt': 1893452400, 'expiresAt': None, 'title': 'Synthetic reset',
                'description': 'Fixture only.'}]}, 'accountId': None, 'rateLimitUpsell': None}
    elif method == 'model/list':
        models = state.get('models', ['gpt-6-astra', 'gpt-5.6-luna'])
        result = {'data': [{'id': m, 'model': m, 'displayName': m.upper(), 'isDefault': i == 0,
                            'description': 'Synthetic model; no model calls.', 'hidden': False,
                            'defaultReasoningEffort': 'medium', 'defaultServiceTier': None,
                            'supportsPersonality': False,
                            'serviceTiers': [{'id': 'fast', 'name': 'Fast',
                                             'description': 'Synthetic fast tier; no paid request.'}],
                            'supportedReasoningEfforts': [{'reasoningEffort': e,
                                                         'description': f'Synthetic {e} effort.'}
                                                        for e in ['low', 'medium', 'high']]} for i, m in enumerate(models)], 'nextCursor': None}
    elif method == 'collaborationMode/list':
        result = {'data': [
            {'name': 'Plan', 'mode': 'plan', 'model': None, 'reasoning_effort': None},
            {'name': 'Default', 'mode': 'default', 'model': None, 'reasoning_effort': None},
        ]}
    elif method == 'thread/list':
        refresh_saved_threads()
        cwd_filter = params.get('cwd')
        if cwd_filter is not None:
            cwds = [cwd_filter] if isinstance(cwd_filter, str) else cwd_filter
            if 'cwd' not in state and cwds:
                state['cwd'] = cwds[0]
            if cwds:
                bind_legacy_threads(cwds[0])
                save()
        else:
            cwds = None
        query = params.get('searchTerm', '').casefold()
        result = {'data': [summary(t) for t in threads
                           if t['archived'] == params.get('archived', False)
                           and (cwds is None or thread_cwd(t['id']) in cwds)
                           and query in ((t.get('name') or '') + ' ' +
                                         (t.get('preview') or '')).casefold()],
                  'nextCursor': None}
    elif method in ('thread/read', 'thread/resume'):
        refresh_saved_threads()
        t = thread_for_id(params.get('threadId'))
        if t is None:
            send({'id': request['id'], 'error': {
                'code': -32001, 'message': 'Synthetic conversation does not exist.'
            }})
            continue
        if method == 'thread/resume' and params.get('cwd') is not None:
            t['cwd'] = params['cwd']
            save(t)
        result = {'thread': summary(t)} if method == 'thread/read' else thread_response(t)
    elif method == 'thread/start':
        cwd = params.get('cwd', os.getcwd())
        t = {'id': f'qa-created-{uuid.uuid4().hex}', 'name': None, 'preview': '',
             'archived': False, 'cwd': cwd}
        threads.append(t)
        save(t)
        result = thread_response(t)
    elif method == 'thread/fork':
        if params.get('excludeTurns') is not True or params.get('deferGoalContinuation') is not True:
            send({'id': request['id'], 'error': {
                'code': -32602, 'message': 'Synthetic fork requires excluded turns and deferred goals.'}})
            continue
        copied_turns, cursor = history(t['id'])
        while cursor:
            older, cursor = history(t['id'], cursor)
            copied_turns.extend(older)
        forked = {'id': f'qa-forked-{uuid.uuid4().hex}', 'name': t.get('name'),
                  'preview': t.get('preview', ''), 'archived': False, 'cwd': thread_cwd(t['id']),
                  'settings': json.loads(json.dumps(t.get('settings', {}))),
                  'fixtureTurns': json.loads(json.dumps(copied_turns))}
        threads.append(forked)
        save(forked)
        trace({'method': method, **params, 'forkedThreadId': forked['id'], 'cwd': forked['cwd']})
        result = thread_response(forked)
    elif method == 'thread/compact/start':
        if set(params) != {'threadId'}:
            send({'id': request['id'], 'error': {
                'code': -32602, 'message': 'Synthetic compaction accepts only threadId.'}})
            continue
        turn, items, stop_event = command_turn(t['id'], ['contextCompaction'])
        trace({'method': method, 'threadId': t['id'], 'turnId': turn['id']})
        send({'id': request['id'], 'result': {}})
        threading.Thread(target=finish_command_turn,
                         args=(t['id'], turn, items, stop_event), daemon=True).start()
        continue
    elif method == 'review/start':
        target = params.get('target')
        valid_target = isinstance(target, dict) and target.get('type') in (
            'uncommittedChanges', 'baseBranch', 'commit', 'custom')
        required = {'baseBranch': 'branch', 'commit': 'sha', 'custom': 'instructions'}
        if valid_target and target['type'] in required:
            field = required[target['type']]
            valid_target = isinstance(target.get(field), str) and bool(target[field].strip())
        if not valid_target or params.get('delivery') != 'inline':
            send({'id': request['id'], 'error': {
                'code': -32602, 'message': 'Synthetic review requires a valid target and inline delivery.'}})
            continue
        turn, items, stop_event = command_turn(
            t['id'], ['enteredReviewMode', 'agentMessage', 'exitedReviewMode'])
        trace({'method': method, **params, 'turnId': turn['id']})
        begin_command_turn(t['id'], turn, items)
        send({'id': request['id'], 'result': {'reviewThreadId': t['id'], 'turn': turn}})
        threading.Thread(target=finish_command_turn,
                         args=(t['id'], turn, items, stop_event, True), daemon=True).start()
        continue
    elif method == 'thread/settings/update':
        allowed = {'threadId', 'model', 'effort', 'serviceTier', 'collaborationMode'}
        mode = params.get('collaborationMode')
        if (set(params) - allowed or
                ('collaborationMode' in params and not valid_collaboration_mode(mode)) or
                ('model' in params and params['model'] not in state.get(
                    'models', ['gpt-6-astra', 'gpt-5.6-luna'])) or
                ('effort' in params and params['effort'] not in ('low', 'medium', 'high')) or
                ('serviceTier' in params and params['serviceTier'] not in (None, 'fast'))):
            send({'id': request['id'], 'error': {
                'code': -32602, 'message': 'Synthetic thread settings are invalid.'}})
            continue
        settings = t.setdefault('settings', {})
        for field in ('model', 'serviceTier', 'collaborationMode'):
            if field in params:
                settings[field] = params[field]
        if 'effort' in params:
            settings['reasoningEffort'] = params['effort']
        if mode:
            settings['model'] = mode['settings']['model']
            settings['reasoningEffort'] = mode['settings']['reasoning_effort']
        save(t)
        effective = thread_settings(t)
        trace({'method': method, **params})
        notification_settings = {key: value for key, value in effective.items()
                                 if key != 'reasoningEffort'}
        notification_settings['effort'] = effective['reasoningEffort']
        send({'method': 'thread/settings/updated', 'params': {
            'threadId': t['id'], 'threadSettings': notification_settings}})
        result = {}
    elif method == 'thread/turns/list':
        turns, next_cursor = history(params.get('threadId'), params.get('cursor'))
        if params.get('itemsView') == 'notLoaded':
            turns = [{**turn, 'items': [], 'itemsView': 'notLoaded'} for turn in turns]
        result = {'data': turns, 'nextCursor': next_cursor}
    elif method == 'thread/items/list':
        turns, history_cursor = history(params.get('threadId'))
        visited = set()
        while history_cursor and history_cursor not in visited:
            visited.add(history_cursor)
            older, history_cursor = history(params.get('threadId'), history_cursor)
            turns = older + turns
        turn = next((turn for turn in turns if turn['id'] == params.get('turnId')), None)
        if turn is None:
            send({'id': request['id'], 'error': {
                'code': -32602, 'message': 'Synthetic item request needs an existing turn.'}})
            continue
        items = turn['items']
        if params.get('sortDirection') == 'desc':
            items = list(reversed(items))
        cursor = params.get('cursor')
        offset = int(cursor.removeprefix('qa-items:')) if cursor else 0
        limit = max(1, int(params.get('limit', 100)))
        data = [{'turnId': turn['id'], 'item': item} for item in items[offset:offset + limit]]
        next_cursor = f'qa-items:{offset + limit}' if offset + limit < len(items) else None
        result = {'data': data, 'nextCursor': next_cursor, 'backwardsCursor': None}
    elif method == 'thread/name/set':
        refresh_saved_threads()
        for t in threads:
            if t['id'] == params['threadId']:
                t['name'] = params['name']
                save(t)
        result = {}
    elif method in ('thread/archive', 'thread/unarchive'):
        refresh_saved_threads()
        t = next(t for t in threads if t['id'] == params['threadId'])
        t['archived'] = method == 'thread/archive'
        save(t)
        result = {'thread': summary(t)} if method == 'thread/unarchive' else {}
    elif method == 'turn/start':
        t = thread_for_id(params.get('threadId'))
        if t is None:
            send({'id': request['id'], 'error': {
                'code': -32001, 'message': 'Synthetic conversation does not exist.'
            }})
            continue
        if 'collaborationMode' in params:
            if not valid_collaboration_mode(params['collaborationMode']):
                send({'id': request['id'], 'error': {
                    'code': -32602, 'message': 'Synthetic turn collaboration mode is invalid.'}})
                continue
            t.setdefault('settings', {})['collaborationMode'] = params['collaborationMode']
            t['settings']['model'] = params['collaborationMode']['settings']['model']
            t['settings']['reasoningEffort'] = params['collaborationMode']['settings']['reasoning_effort']
            save(t)
        if params.get('cwd') is not None:
            t['cwd'] = params['cwd']
            save(t)
        cwd = thread_cwd(t['id'])
        trace({'method': method, 'threadId': params.get('threadId'),
               'input': params.get('input', []), 'model': params.get('model'),
               'effort': params.get('effort'), 'cwd': cwd,
               'collaborationMode': params.get('collaborationMode'),
               'serviceTier': params.get('serviceTier')})
        turn_id, item_id = next_turn_id(params['threadId'])
        stop_event = threading.Event()
        text = ' '.join(part.get('text', '') for part in params.get('input', [])
                        if part.get('type') == 'text')
        late_command_after_stop = '[qa-late-command-after-stop]' in text
        send({'id': request['id'], 'result': {'turn': {'id': turn_id, 'status': 'inProgress', 'items': []}}})
        threading.Thread(
            target=run_turn,
            args=(params['threadId'], turn_id, item_id, stop_event, cwd, late_command_after_stop),
            daemon=True
        ).start()
        continue
    elif method == 'turn/steer':
        thread_id = params.get('threadId')
        expected_turn_id = params.get('expectedTurnId')
        trace({'method': method, 'threadId': thread_id, 'expectedTurnId': expected_turn_id,
               'input': params.get('input', [])})
        with history_lock:
            active = active_turns.get(thread_id)
        if not active or active['turnId'] != expected_turn_id:
            send({'id': request['id'], 'error': {
                'code': -32001, 'message': 'Synthetic active turn does not match expectedTurnId.'
            }})
            continue
        text = ' '.join(part.get('text', '') for part in params.get('input', []) if part.get('type') == 'text')
        delta = f'\n- Steering accepted for {expected_turn_id}: {text}'
        with history_lock:
            active['item']['text'] += delta
            active['turn']['items'] = [dict(active['item'])]
        send({'id': request['id'], 'result': {'turnId': expected_turn_id}})
        send({'method': 'item/agentMessage/delta', 'params': {
            'threadId': thread_id, 'turnId': expected_turn_id,
            'itemId': active['item']['id'], 'delta': delta,
        }})
        continue
    elif method == 'turn/interrupt':
        with history_lock:
            active = active_turns.get(params.get('threadId'))
        if not active or active['turnId'] != params.get('turnId'):
            send({'id': request['id'], 'error': {
                'code': -32001, 'message': 'Synthetic active turn does not match turnId.'
            }})
            continue
        active['stopEvent'].set()
        result = {}
    else:
        send({'id': request['id'], 'error': {'code': -32601, 'message': 'Synthetic backend method not implemented: ' + str(method)}})
        continue
    send({'id': request['id'], 'result': result})
