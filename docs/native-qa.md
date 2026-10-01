# Native QA without model calls

Run `./scripts/native-qa.sh`. It builds an isolated QA bundle, copies the synthetic backend into a temporary directory, creates a Git fixture with a committed baseline, and prints the fixture path. Open that path with **Open Project** in the QA app. The QA bundle has separate preferences from the normal app. `CODEX_GUI_WORKSPACE_ROOT` directs task records and checkouts into the run's temporary `task-workspaces` directory, so task workspace checks preserve the normal app's saved workspaces.

The backend never calls a model or edits project files. Its model names are fixtures. Rename/archive choices are saved only in its temporary JSON file. Each run uses a unique bundle ID so Launch Services cannot reuse an older QA app. Before interacting, verify that the launched app's Codex executable is the copied `qa-backend.py`, especially if another QA session is open.

## Reading checks

Select **Markdown and streaming**. Inspect headings, emphasis, the documentation link, nested and numbered lists, both code blocks, and `FINAL_READING_MARKER`. Resize the window and toggle Changes. Text and copy controls should fit. Expand the 1,000-line command output and inspect its literal punctuation.

Send any short message to start a roughly 32-second synthetic stream. Scroll to an earlier message while it runs. The reading position should stay stable; **Latest Message** should return to the end. Copy each code block into the composer and compare its indentation and trailing newline with `scripts/qa-backend.py`.

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
