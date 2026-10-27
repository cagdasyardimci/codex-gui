# Composer slash commands

Type `/` at the start of the draft to discover available commands and enabled skills. The [command registry](../Sources/CodexGUI/Application/Reducers/Composer/SlashCommandRegistry.swift) owns command names, argument forms and descriptions; the [parser](../Sources/CodexGUI/Application/Reducers/Composer/SlashCommandParser.swift) owns recognition. Keep those definitions authoritative instead of copying a command table here.

## Syntax and intent

Commands are composer actions rather than shell input: arguments have no shell quoting or escape syntax. Paths, URLs and slashes later in prose remain ordinary text. Use `//status` to send literal `/status`. Invalid input retains the draft. Selecting a skill attaches it to the next message without sending that message. The composer shows the selection as an inline mention. Normal text selection and deletion remove it while preserving other draft content and attachments. The mention remains separate from the plain draft and is submitted using its selected skill name and path. Both the inline list and `/skills` picker search internal names, display names and descriptions with case-insensitive substring matching.

Forking copies conversation history in the source checkout; task checkout creation is a separate Git operation. Plan toggling without a prompt changes next-turn mode without starting a model turn. Preserve the remaining prompt text when invoking plan mode with a prompt.

## Lifecycle

Compaction acknowledgement does not establish completion. Review and compaction events can precede their request replies. Apply [protocol safeguards](cli-compatibility.md#protocol-lifecycle-safeguards) and [ownership and recovery](architecture.md#ownership-and-recovery) to command execution.

An uncertain plan update needs a matching settings event or an acknowledged explicit reapply: conversation reads do not report collaboration mode. Keep an explicit recovery choice after reconnection rather than inferring the mode from history.

Context occupancy uses the last reported active-context size and model context window. Last-request input and cumulative token totals are different quantities; absent values must remain unavailable. Selecting a saved chat resumes it to establish a subscription and replay usage, while background reads remain unsubscribed.

Follow [validation](validation.md) for checks and [AppKit conventions](../CONVENTIONS.md#appkit-behavior-and-accessibility) for deferred command dialogs.
