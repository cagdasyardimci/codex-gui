# Conversation activity presentation

## Current behavior

Clicking a generic command's title next to its terminal icon toggles the Shell panel through the same disclosure action as its chevron.

The conversation presents assistant commentary and answers as ordinary messages. Between messages, consecutive command activities in the same turn form a compact activity group. A group never absorbs another turn, a user message, assistant commentary, or an image view. Repeated operations remain separate observations, including repeated reads of the same file.

The group header has an icon, a summary such as “Read files, ran commands”, and a disclosure chevron immediately after the summary. Its list starts collapsed. A single action uses its own expandable header instead of a separate group header. Each command-backed row can independently reveal its command details; those details start collapsed. Closing a group does not forget which of its commands were expanded. Closed headers retain counts of failed, declined, and interrupted commands, counted once per source item.

Activity disclosure chevrons appear only while the pointer is over their header row. Group, command, read, search, file-list and image rows share this behavior. Pointer movement into an expanded Shell panel hides its row's chevron. The disclosure button retains its layout, pointer hit region, keyboard focus and accessible label when the glyph is absent. Hover does not change expansion or move text. Activity titles and underlined file-link text use the primary label color while their header is hovered and the secondary label color at rest; file underlines and failure badges remain visible.

Activity rows use secondary system text and small icons, without a card background. A read shows a book icon, “Read”, and an underlined filename. A search shows a search icon and the reported query and target. A generic command shows a terminal icon and “Ran” followed by a single-line preview. Previews normalize whitespace and truncate at the available width; tooltips and expanded details preserve the full original command.

Command details appear directly below the row in a rounded, subtly bordered Shell panel. The header and panel share the full width and leading edge of the transcript row. The panel contains selectable monospaced command text beginning with `$`, the reported output, and execution details. Long output scrolls inside a bounded panel. Failure and declined states remain visible in the compact row. Inner output scroll position and text selection survive output updates and closing or reopening details, and reset with transcript ownership. A zero exit code is not inferred from completion alone. Read-file navigation and command disclosure are separate actions. A file opens using the system application; a relative path resolves against its command working directory, falling back to the owning project only when a working directory was not reported.

An image view has its own “Viewed an image” disclosure row and an aspect-preserving thumbnail. It starts expanded and opens the local image when clicked. An unavailable image gets an explicit unavailable state. The image loader bounds its cache and decodes previews away from the main actor. Empty, unsupported tool placeholders do not produce blank transcript cards.

A per-turn status row appears after its user request and before the assistant work. Backend timestamps drive “Working for …” and the completed duration. Failure and interruption use their reported turn outcomes. Historical turns with no timing metadata do not acquire an invented duration. Only the matching active thread and turn can show a ticking working duration. An unfinished turn without active ownership shows “Status unavailable”; a later turn cannot assign it a completion outcome. A local UI timer refreshes only visible status labels while work is active.

## Data and ownership

The client decodes `commandActions` variants `read`, `search`, `listFiles`, and `unknown`, with command, file, and query fields. It also decodes image-view paths, and turn timing fields. It does not classify activity by inspecting shell program names. Missing or unrecognized action metadata falls back to “Ran” with the original command, including compound commands and wrappers.

Canonical conversation entries retain their existing identities and structured activity data. Streaming output updates that data in order; item completion supplies authoritative output and status. Projection derives display rows without rewriting execution records or command lifetime barriers. Thread and workspace ownership remain part of every accepted backend event.

The AppKit transcript uses separate display rows for messages, group headers, action rows, and turn status. Stable display identities derive from source item identities and action order. Navigation, bookmarks, failures, and the turn rail map display rows back to their source entries. Jumping to an item inside a closed group opens the group. Disclosure state belongs to the transcript context and resets when its workspace or conversation identity changes. Stale callbacks must not mutate another transcript.

Output updates preserve the reader's scroll anchor unless the reader is following the latest content. Disclosure changes preserve the current reading position. Layout measurement and rendering share geometry. Consecutive rows in one activity group have no extra inter-row gap; message and group boundaries keep ordinary transcript spacing. Status ticks do not reparse messages or reconstruct activity lists. Controls support keyboard focus, accessible names, and both system appearances.

For verification commands and evidence requirements, see [validation](validation.md).
