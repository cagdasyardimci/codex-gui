# Composer slash commands

Type `/` at the start of the draft to discover available commands. The [Tauri command registry](../desktop/core/src/slash_commands.rs) owns recognition and argument forms. The [command router](../desktop/src-tauri/src/navigation/slash_commands.rs) enables actions against the selected workflow, backend capabilities and captured draft. The [Swift registry](../Sources/CodexGUI/Application/Reducers/Composer/SlashCommandRegistry.swift) defines the Mac reference.

## Syntax and intent

Commands are composer actions rather than shell input: arguments have no shell quoting or escape syntax. Paths, URLs and slashes later in prose remain ordinary text. Use `//status` to send literal `/status`. Invalid input retains the draft. Selecting a skill attaches it to the next message without sending that message; editing its inline mention must preserve other draft content and attachments.

Forking copies conversation history in the source checkout. The `/fork` command copies the saved chat, while **Branch in new chat** copies history through the selected response's turn and preserves the source draft. Task checkout creation is a separate Git operation.

Editing a sent prompt forks before the captured finished turn. The [revision workflow](../desktop/src-tauri/src/navigation/prompt_revision.rs) persists the revised prompt and retained attachments before requesting the fork, then sends literally when the captured selection can adopt the destination. A failed or superseded selection leaves the prepared draft with the fork.

Plan toggling without a prompt changes next-turn mode without starting a model turn. Preserve the remaining prompt text when invoking plan mode with a prompt.

## Lifecycle

Compaction acknowledgement does not establish completion. Review and compaction events can precede their request replies. Apply [protocol safeguards](cli-compatibility.md#protocol-lifecycle-safeguards) and [ownership and recovery](architecture.md#ownership-and-recovery) to command execution.

An uncertain plan update needs a matching settings event or an acknowledged explicit reapply: conversation reads do not report collaboration mode. Keep an explicit recovery choice after reconnection rather than inferring the mode from history.

Context occupancy uses the last reported active-context size and model context window. Last-request input and cumulative token totals are different quantities; absent values must remain unavailable. Selecting a saved chat resumes it to establish a subscription and replay usage, while background reads remain unsubscribed.

Follow [validation](validation.md) for checks and [AppKit conventions](../CONVENTIONS.md#appkit-behavior-and-accessibility) for deferred command dialogs.

## Context mentions

Use the composer plus button or type `@` at a token boundary to open the [context menu](../Sources/CodexGUI/Features/Conversation/ConversationViewController/ConversationViewController+MentionMenu.swift). Opening it with the plus button preserves the draft and selection. Choosing an action from `@` replaces only the active mention token. Selections expire when the draft owner changes.

The source draft remains with its current project or chat when another project is selected. Plugin installation and configuration retain the [Settings presentation lifetime](settings.md#configuration-ownership).

Plan mode uses the same availability rules and command path as `/plan`, preserving the draft outside the mention token. Disabled actions cannot be selected or invoked and are skipped by keyboard navigation.
