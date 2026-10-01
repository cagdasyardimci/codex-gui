# Native QA without model calls

Run `./scripts/native-qa.sh`. It builds an isolated QA bundle, copies the synthetic backend into a temporary directory, creates a Git fixture with a committed baseline, and prints the fixture path. Open that path with **Open Project** in the QA app. The QA bundle has separate preferences from the normal app. `CODEX_GUI_WORKSPACE_ROOT` directs task records and checkouts into the run's temporary `task-workspaces` directory, so task workspace checks preserve the normal app's saved workspaces.

The backend never calls a model or edits project files. Its model names are fixtures. Rename/archive choices are saved only in its temporary JSON file. Each run uses a unique bundle ID so Launch Services cannot reuse an older QA app. Before interacting, verify that the launched app's Codex executable is the copied `qa-backend.py`, especially if another QA session is open.

## Reading checks

The static reading fixture contains the canonical **Markdown Rendering Test** prompt, including
its instruction prefix, once as a user message and once as an assistant message. Inspect both
roles; a formatted assistant message alone does
not establish that user messages use the renderer. Both must retain every heading, list item,
table cell, code line, link label, escape, and trailing marker. User-message background and
alignment may differ, but Markdown syntax must receive the same supported formatting.

Select **Markdown and streaming**. Inspect three heading levels; bold, italic, combined bold/italic,
and strikethrough; the documentation link; nested, numbered, and checked/unchecked task lists;
the quote with its nested list; the thematic rule; and both code blocks. The table has left,
center, and right alignment, styled cells, a link, and Unicode. At wide and minimum window sizes,
with Changes open and closed, its long cell must wrap and every row must remain readable.
Check `TABLE_END_MARKER`, `CODE_END_MARKER`, and `FINAL_MARKER` below their corresponding blocks. Expand the
1,000-line command output and inspect its literal punctuation.

Repeat in light and dark appearance. Select and copy ordinary text, a heading, and table text
into the composer. Unicode before `UNICODE_BOLD_MARKER` and `UNICODE_CODE_MARKER` must not shift
their styling or selection ranges. Copy each code block into the composer and compare its
indentation, literal punctuation, Unicode, and trailing newline with `scripts/qa-backend.py`.
Check that each copy button belongs to its corresponding block and remains reachable after resize.

The fixture also checks reference links, an ordered list starting at three, nested quotations,
an escaped table pipe, indented code, decoded entities, and an explicit hard break. The display
math uses `$$` delimiters; the Mermaid fence describes a three-node flowchart. Record whether
each rich probe is rendered or shown as literal source, and confirm `FINAL_MARKER` remains
readable. Their presence in a fixture or a passing protocol check does not establish rich
rendering support.

For supported display math, inspect that the complete equation is centered in the available
message content width. For the supported Mermaid flowchart, all three nodes, their full labels,
and both arrows must fit inside the card at wide/narrow widths. The rightmost **Rendered content**
node must not be cropped at the card edge. Check this after toggling Changes as well as resizing.
Adjacent Python and Swift cards need a visible gap; the indented-code card must end before
`CODE_END_MARKER`. Card backgrounds must not cover the following heading, paragraph, or marker.
Check `TABLE_END_MARKER`, `CODE_END_MARKER`, `FINAL_MARKER`, and `EMPTY_FENCE_END_MARKER` in both
roles. Native checks must use the final gated build; screenshots of an earlier build do not
verify subsequent source fixes.

The supplied reference screenshots show formatted Markdown in user bubbles: styled headings
and inline text, hanging/nested list indents, task markers, quote rails, aligned table cells,
separate monospaced code panels, decoded escapes/entities, and a horizontal rule. Their display
math and Mermaid flowchart render visually; their inline `$E = mc^2$` and raw HTML remain
literal. The GUI comparison screenshots show the same user-message source literally, including
heading markers, formatting delimiters, table pipes, code fences, and link definitions. These
images establish the rendering difference, but do not establish selection, copying, link
activation, appearance handling, streaming, or native view implementation. Check those behaviors
separately after the source and test gates pass.

An additional identical user/assistant edge fixture checks a continuous quote rail across
paragraphs, a nested quote, a long Unicode code line that wraps inside its card, and an empty
code fence followed by `EMPTY_FENCE_END_MARKER`. Inspect these at narrow/wide widths without
changing the canonical screenshot-comparison source.

Send any short message to start a roughly 32-second synthetic stream. Its 16 chunks deliberately
pause with incomplete bold, link, strikethrough, table, and code-fence syntax. Inspect those
intermediate states, then check that the completed result has a native table and code block with
one `STREAM_START_MARKER` and one `STREAM_END_MARKER`. The code includes U+2028 and U+2029 Unicode
separators; copying must preserve them without losing the following text. Scroll to an earlier
message while a second stream runs. The reading position should stay stable; **Latest Message**
should return to the end. Stop a third stream mid-syntax and confirm its accumulated text remains
readable. Switching away and back must preserve the completed and interrupted message text.

`python3 scripts/check-qa-backend.py` checks identical user/assistant source, fixture and rich-probe
completeness, chunk delivery, exact final content, interruption, and history restoration with a
shortened synthetic interval. It does not
verify the renderer, visual appearance, selection, copy buttons, or reading position. Source
inspection and AppKit view tests should separately verify the view hierarchy contains no web
view or SwiftUI host; a screenshot alone cannot establish the rendering implementation.

## Activity presentation checks

Select **Activity groups and details**. Confirm two separate reads of `file with spaces.swift`,
a search row, compact command rows, and a separate image thumbnail. The historical turn reports
2 minutes 4 seconds. Expand a command's Shell details, close its group, then reopen the group:
the command should retain its disclosure state. File links open only the temporary fixture.
The synthetic command with exit code 2 must show failure even though its item status is completed.
Move the pointer onto each activity header: its disclosure chevron should appear. Move away:
the chevron should disappear while the row keeps the same spacing and remains operable by keyboard.

Inspect the long command output by scrolling inside its bounded Shell panel. Resize the window
and check that previews truncate while expanded commands wrap. Send any short message for a
roughly 9-second synthetic command stream. Inspect the live duration, open its details, and
confirm streamed output updates the existing row. Scroll away during streaming, then return
with **Latest Message**. Stop another stream and inspect the interrupted duration. Switch chats
while a command is expanded and check that another chat does not inherit its controls or output.

## Context and native interaction checks

Choose a model and effort, select a conversation, type an unsent multiline draft, resize the window/panes, and quit. Relaunch the same QA bundle with the same `CODEX_EXECUTABLE`, `CODEX_GUI_QA_STATE`, and `CODEX_GUI_WORKSPACE_ROOT` environment paths. Check conversation, draft, model/effort, and layout restoration.

Use search, rename, and archive on **Find rename and archive**. Check keyboard focus and Edit-menu shortcuts, including undo, select-all, copy, and paste. Insert `file with spaces.swift` through the native picker and check the quoted relative path. Repeat reading and control checks in light and dark appearance.

Search is scoped to titles and previews in the current project's active or archived list. After archiving a fixture, enable **Archived**, select it, and use **Restore** to move it back. **Command-F** focuses search.

For an unavailable-model check, first select the Luna fixture and quit. In the temporary `backend-state.json`, set `"models": ["gpt-6-astra"]`, preserving the other fields. Relaunch and confirm that the saved Luna choice remains visible with a warning and Send stays disabled. Restore the model list afterward. This changes only synthetic model availability.

The navigation fixture reports a synthetic change at line 3 of `file with spaces.swift`. Choose the preferred editor in **Settings…** (Command-comma), then use Changes to verify file/line handoff; selecting an editor opens only this temporary file.

The build and QA scripts apply an ad hoc signature to the complete bundle so macOS can associate notification requests with its bundle identity. This is a local development signature, not distribution signing. Settings shows the observed notification permission or request/delivery error. Banner delivery still requires native observation and any macOS permission remains under the user's control.

At the minimum supported window size, inspect the sidebar, composer, and optional inspector. Check that the task status remains visible beside its owning chat, the toolbar status popover exposes account/backend details and recovery, and code-copy buttons sit beside their corresponding blocks. After a synthetic Stop, browse another chat and return to the stopped task; its stopped result must remain visible. Notification permission and banner delivery require a separate native observation; source tests cover only transition selection and owner identity.

VS Code handoff uses its documented [`--goto file:line` interface](https://code.visualstudio.com/docs/configure/command-line). Other chosen applications use macOS file opening; unsupported line navigation and missing-editor fallback are shown in the Changes pane.

Automated checks and synthetic native checks do not establish behavior against a live app-server. Report live-backend evidence separately when reviewing or releasing changes.
