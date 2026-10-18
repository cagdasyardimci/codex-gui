# Composer slash commands

Type `/` at the beginning of the composer to open command completion. Up/Down selects a row, Tab inserts its name, Return executes an available command, and Escape closes completion without changing the draft. IME marked text and Shift-Return keep their normal text-entry behavior. Command availability includes the current checkout, chat, active operation and supported backend settings.

The completion panel follows the composer width and uses compact icon/title/description rows in light and dark appearances. Unavailable commands keep their descriptions; the reason is provided in the row tooltip and accessibility label.

Enabled skills from the current checkout's catalog appear directly under a **Skills** heading, sorted by display name, with descriptions and scope labels. Typing after `/` filters command names and skill names/display names. Arrow keys skip the section heading. Clicking a skill or pressing Tab/Return selects it for the next message and removes only the slash token, preserving the rest of the draft without sending it. `/skills` remains available to open the full picker, including its **No skill** option.

Only an initial `/name` token is a command; leading spaces and tabs are allowed. URLs, paths such as `/Users/example/source.swift`, fenced text and a slash later in a sentence remain ordinary text. Unknown command names and invalid arguments display an error and retain the draft. Use `//status` to send literal `/status` text. Arguments have no shell quoting or escape syntax. `/plan` removes one separating character and preserves the remaining prompt text.

| Syntax | Behavior |
| --- | --- |
| `/new` | Start a fresh chat in the source checkout. |
| `/resume [thread-id]` | Pick or resume a saved chat available in the current checkout. |
| `/fork` | Copy the current conversation into a new conversation in the same source checkout. |
| `/rename [name]` | Rename directly, or open the native rename dialog. |
| `/archive` | Archive the current chat. |
| `/delete` | Open the native deletion confirmation. |
| `/compact` | Request server compaction and wait for its turn lifecycle. |
| `/review [uncommitted\|base <branch>\|commit <sha>\|custom <instructions>]` | Choose a target or start an inline server review. |
| `/model [model-id]` | Choose a model from the backend's current catalog. |
| `/reasoning [effort]` | Choose an effort supported by the selected model. |
| `/fast [on\|off]` | Toggle or set the advertised fast service tier. |
| `/permissions [ask\|auto\|full]` | Choose approvals; full access uses the existing confirmation. |
| `/plan [prompt]` | Toggle plan mode without a model turn, or send the supplied prompt in plan mode. |
| `/status` | Show execution/account status and the selected chat's reported token usage. |
| `/skills` | Open the skill picker. |
| `/mention` | Open the file/context picker. |
| `/diff` | Open the selected chat's Changes panel, which displays reported changes and the chosen review turn. |
| `/copy` | Copy the latest nonempty assistant response in the viewed chat. |

`/fork` copies conversation history; it creates no Git branch or worktree and does not start a model turn. Managed task checkouts remain bound to their chat, so fork and new-chat actions require selecting the source checkout. Archived chats and pending or uncertain operations restrict chat-changing commands. Shared ownership, recovery and command cleanup barriers follow [architecture](architecture.md#ownership-and-recovery); deferred dialogs follow the [AppKit conventions](../CONVENTIONS.md#appkit-behavior-and-accessibility).

Fast mode requires a service tier advertised by the selected model's catalog and sends that tier's actual ID. [FastModeAvailability](../Sources/CodexGUI/Application/Reducers/Preferences/FastModeAvailability.swift) owns tier selection. Switching to an unsupported model while fast mode is enabled blocks Send until fast mode is disabled.

Compaction's `{}` reply acknowledges the request, rather than proving completion. Review and compaction may publish lifecycle events before their replies.

An uncertain plan update needs a matching settings event or an acknowledged explicit reapply; conversation read/resume responses do not report collaboration mode. After reconnecting, `/plan` presents **Reapply Plan**, **Reset Default** and **Cancel**.

Last-request input and cumulative conversation usage are token counts, not current context occupancy. Occupancy is labeled **not reported**, and absent server values remain unavailable.

## Validation routing

Follow [validation](validation.md) for test-host execution and evidence requirements, and [native QA](native-qa.md) for synthetic interaction checks and isolation limits.
