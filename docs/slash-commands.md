# Composer slash commands

Type `/` at the beginning of the composer to open command completion. Up/Down selects
a row, Tab inserts its name, Return executes an available command, and Escape closes
completion without changing the draft. IME marked text and Shift-Return keep their
normal text-entry behavior. Command availability includes the current checkout, chat,
active operation and supported backend settings.

The completion panel follows the composer width and uses compact icon/title/description
rows in light and dark appearances. Unavailable commands keep their descriptions;
the reason is provided in the row tooltip and accessibility label.

Only an initial `/name` token is a command; leading spaces and tabs are allowed.
URLs, paths such as `/Users/example/source.swift`, fenced text and a slash later in a
sentence remain ordinary text. Unknown command names and invalid arguments display
an error and retain the draft. Use `//status` to send literal `/status` text. Arguments
have no shell quoting or escape syntax. `/plan` removes one separating character and
preserves the remaining prompt text.

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

`/fork` copies conversation history; it creates no Git branch or worktree and does not
start a model turn. Managed task checkouts remain bound to their chat, so fork and
new-chat actions require selecting the source checkout. Archived chats and pending
or uncertain operations restrict chat-changing commands. Local dialogs capture their
original checkout, chat, generation, draft and attachments; a stale result cannot
apply to a replacement selection or edited draft.

Fast mode requires a service tier advertised by the selected model's catalog. The app
recognizes the advertised priority tier or a tier identified/named Fast, captures that
tier's actual ID, and sends that ID. It does not invent a priority tier. Switching to
an unsupported model while fast mode is enabled blocks Send until fast mode is disabled.

Compaction's `{}` reply acknowledges the request, rather than proving completion.
Review and compaction may publish lifecycle events before their replies. Pending
commands and independently running shell commands continue to protect execution,
cleanup and quit until their own outcomes are known. An uncertain plan update needs
a matching settings event or an acknowledged explicit reapply; conversation read/resume
responses do not report collaboration mode. After reconnecting, `/plan` presents
**Reapply Plan**, **Reset Default** and **Cancel**. Last-request input and cumulative
conversation usage are token counts, not current context occupancy. Occupancy is
labeled **not reported**, and absent server values remain unavailable.

## Validation

Run `make check` with the repository's Swift Testing framework/plugin/linker flags.
The added suites are `SlashCommandRegistryTests`, `SlashCommandParserTests`,
`SlashCommandProtocolTests`, `SlashCommandAppServerTests`,
`ComposerCommandReducerTests`, `ComposerCommandRuntimeTests`,
`ComposerSlashCommandTests` and `SlashCommandPresentationTests`. The Makefile keeps
shown-window tests in separate test-host lifecycles. Require explicit completion
summaries; a process exit code alone does not establish that all tests completed.

Run `python3 scripts/check-qa-backend.py` for synthetic compact/review/fork lifecycles,
event-before-response ordering, plan/settings persistence, model metadata and token
usage. Run `git diff --check`, build with `./scripts/bundle.sh`, and verify the bundle
with `codesign --verify --deep --strict --verbose=2 .build/CodexGUI.app`.

The completed implementation was validated with 12 Python driver regressions,
275 Swift files passing the custom style check, a successful build and synthetic
fixture checker, and a signed debug app bundle. The focused command and legacy
regression run explicitly passed 78 tests in 10 suites. The broad `make check`
host exited successfully without a final completion summary, so the same built
artifact was inventoried and reconciled in 74 separate hosts: all 515 discovered
test declarations across 68 suites had explicit passing summaries. Two shown-window
methods and the five Navigation controller methods ran individually to preserve
test-host lifecycles. These 515 declarations include the focused tests; the counts
are not additive. `git diff --check` also passed.

Native Computer Use checks used isolated, signed apps and the synthetic backend,
with no live inference. Initial exploration on source `6e40610e…3d892` covered dark
completion navigation, rename/delete confirmation cancellation with retained drafts,
file attachments, model/permission selection, status availability labels, inline Plan
and attachment wire input, Stop, compact/review completion, resume/skills pickers and
a distinct saved fork at the same source cwd. The fork trace required both
`excludeTurns: true` and `deferGoalContinuation: true`. The initial model picker's
plain-Return dismissal exposed a focus bug; the fix has a real-window regression test.
Those exploratory scenarios were not all repeated on the final app.

The final app `local.codexgui.nativeqa.uoozzt9m`, built from source SHA256
`dcdc5bfcc9880a0e2afd485acd47402bef9b7febbf30611a0db5117cfd9f087e`,
passed the required native retest: `/mo` filtering and Tab preserve composer focus;
plain Return opens and retains the model and permissions pickers; Escape retains
their drafts; `/skills` focuses search and accepts the selected skill. Completion
arrows, Tab and continued typing retain focus. Unknown commands show an error and
retain the draft; `//doesnotexist` sends the exact literal `/doesnotexist` in the
verified fixture cwd. Native Stop displays the interrupted/stopped state. Both
isolated apps and backend processes were quit after QA, and the final binary/backend
hashes remained unchanged. The final screenshots are
[`model filtering`](/tmp/slash-qa-final-model-filter.png),
[`model after Return`](/tmp/slash-qa-final-model-enter.png),
[`permissions after Return`](/tmp/slash-qa-final-permissions-enter.png),
[`unknown command`](/tmp/slash-qa-final-unknown-command.png) and
[`Stop`](/tmp/slash-qa-final-stop.png).

Native observations cover dark appearance only. Actual IME input, reasoning-slider
arrow selection, uncertain-outcome dialogs and full native acceptance of fast/new/
archive/diff/copy were not established. Delete's final destructive action was not
pressed. Compact/review Stop behavior has automated runtime evidence; their short
synthetic lifecycles prevented a useful native Stop observation. Live app-server
compatibility and actual clipboard behavior remain separate evidence channels;
[native QA](native-qa.md) describes the isolated synthetic workflow.

## Integration on main

The implementation was applied as a patch on top of `ad9276f`, preserving the newer
native Markdown rendering, code-copy hover styling, turn timing and window behavior.
Backend event matching uses main's timestamped action/domain-event signatures.
The synthetic checker retains both the Markdown fixtures and slash-command fixtures.

The integrated tree passed custom formatting for 295 Swift files, the 12 style-driver
and 6 test-runner checks, compilation, and the combined synthetic backend checker.
All 576 discovered Swift test declarations across 73 suites passed with explicit
summaries in 80 isolated hosts. The standard combined `make check` host still exits
without its final summary and is correctly rejected by main's strict runner; the
isolated inventory reconciliation establishes completion without disabling that gate.
Two outdated Markdown tests also failed on pristine `ad9276f`: they assumed sibling
stacking order and the old code-block paragraph spacing. A separate test-only commit
identifies copy controls by stable labels and retains the current 16-point bottom
padding plus 16-point following-block gap. No rendering behavior was changed.

Each commit boundary was built and tested from its staged tree, independently of the
remaining unstaged implementation. Native observations above describe pre-integration
artifacts; they do not establish live UI or live backend proof for the integrated tree.
