# Codex CLI compatibility

Codex GUI communicates with the installed `codex app-server` process over its newline-delimited JSON protocol. The app-server protocol is experimental, so compatibility is based on tested CLI versions rather than a promise that every newer release will keep the same methods and fields.

## Current policy

- **Tested baseline:** Codex CLI 0.153.2.
- **Older versions:** rejected by the app's version check because they are below the supported protocol baseline.
- **Newer versions:** accepted by the current version check, but unverified until the compatibility procedure below passes. Their experimental protocol may have changed.

The app sends `experimentalApi: true` in `initialize` because it uses methods and fields marked experimental by the installed protocol. This is a client opt-in. It does not mean the server negotiated or guaranteed support for every experimental method the app uses.

The experimental message queue subset was exercised against installed CLI 0.164.0 with an isolated local provider: pagination, add/update/reorder/delete, rejection of start during an active turn, interrupt retention and selected-entry Resume. This does not promote 0.164.0 to a fully verified baseline. Queue ownership and fallback follow [architecture](architecture.md#ownership-and-recovery).

Backend diagnostic redaction is pattern-based, so unnamed secrets, unusual encodings and truncated values can remain visible. Review reports before sharing them. Buffer limits and recognized patterns belong to [BackendDiagnostics](../Sources/CodexGUI/CodexClient/Diagnostics/BackendDiagnostics.swift).

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

Remote-control management is an optional experimental capability. Its protocol version, lifecycle, and acceptance limits are owned by [remote access](remote-access.md).

## Protocol lifecycle safeguards

JSONL framing must split on byte LF (`0x0A`), since Unicode line separators may occur inside JSON strings. Resolve unsupported interactive requests with the appropriate error, decline or cancellation response and visible feedback. Preserve method-specific acknowledgement/completion handling and events arriving before responses. Mutation uncertainty follows [recovery](architecture.md#ownership-and-recovery); composer-specific distinctions belong to [slash commands](slash-commands.md#lifecycle). Inspect [interaction handling](../Sources/CodexGUI/CodexClient/AppServer/AppServer+Interactions.swift) and [notifications](../Sources/CodexGUI/CodexClient/AppServer/AppServer+Notifications.swift) for concrete wire behavior.
