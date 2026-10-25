# Codex CLI compatibility

Codex GUI communicates with the installed `codex app-server` process over its newline-delimited JSON protocol. The app-server protocol is experimental, so compatibility is based on tested CLI versions rather than a promise that every newer release will keep the same methods and fields.

For agent task routing, see [agent workflow](agent-workflow.md).

## Current policy

- **Tested baseline:** Codex CLI 0.153.2.
- **Older versions:** rejected by the app's version check because they are below the supported protocol baseline.
- **Newer versions:** accepted by the current version check, but unverified until the compatibility procedure below passes. Their experimental protocol may have changed.

The app sends `experimentalApi: true` in `initialize` because it uses methods and fields marked experimental by the installed protocol. This is a client opt-in. It does not mean the server negotiated or guaranteed support for every experimental method the app uses.

Backend details stay in memory for the current process connection and are limited to the latest 8 KiB of stderr. The display redacts common API-key and token forms, including named credential assignments, Bearer values, and `sk-`-prefixed keys. Redaction is pattern-based and cannot identify every possible secret format. Quoted assignment values can contain spaces, but unnamed secrets, unquoted multi-word values, and truncated or unusual encodings may remain visible. Review the report before copying or sharing it.

Conversation management requests, listing validation and pagination are implemented in [AppServer requests](../Sources/CodexGUI/CodexClient/AppServer/AppServer+Requests.swift). Chat-list filtering searches loaded titles and previews. Message search separately searches loaded conversation content and can fetch more history. Neither uses the experimental server-side `thread/search` method. Unsupported management requests surface their backend error in the app.

Overlapping list pages preserve backend order and retain the first occurrence of each thread ID. Every returned row is validated before duplicate IDs are removed, so a repeated ID cannot hide invalid data.

CLI version probing has a 10-second deadline and runs away from the main actor. A stalled or continuously writing `--version` child cannot leave the interface waiting indefinitely.

## Verifying a CLI upgrade

Identify the executable selected by [AppServer executable selection](../Sources/CodexGUI/CodexClient/AppServer/AppServer+Executable.swift). The shell's `codex` may resolve differently. Use that selected executable for the version and schema commands below.

For each CLI version proposed as supported:

1. Record the exact `codex --version` output.
2. Generate that version's JSON schema with `codex app-server generate-json-schema --experimental --out <temporary-directory>`.
3. Check every request, notification, server request, and response shape used by the app against the generated schema. Pay particular attention to permissions, command and file approvals, questions, turn events, and thread history methods.
4. Run the relevant automated checks under [validation](validation.md).
5. Run read-only live checks for `initialize`, account status, model listing, and thread listing.
6. Observe the affected behavior in a disposable repository and record the results.

Update the tested-version record only after these checks pass. A successful handshake or generated schema alone does not establish full compatibility.

## Capability assessment

Distinguish app-server APIs, configured agent tools, host facilities and GUI controls. Trace support through `CodexService`, wire requests/responses, notifications and server requests, scoped state transitions and presentation. Schema entries and enabled flags alone do not establish GUI support. Host-dependent facilities such as computer use also require a functioning tool provider and permission path.

Remote-control management is an optional experimental capability. Its protocol version, lifecycle,
and acceptance limits are owned by [remote access](remote-access.md).

## Protocol lifecycle safeguards

JSONL framing uses byte LF (`0x0A`); Unicode line separators may occur inside JSON strings. Resolve unsupported interactive requests with the appropriate error, decline or cancellation response and visible feedback. Preserve method-specific acknowledgement/completion handling, events arriving before responses and uncertain-write recovery. Do not automatically replay possibly accepted mutations or approvals. See [interaction handling](../Sources/CodexGUI/CodexClient/AppServer/AppServer+Interactions.swift), [notifications](../Sources/CodexGUI/CodexClient/AppServer/AppServer+Notifications.swift), and [slash-command lifecycle contracts](slash-commands.md).
