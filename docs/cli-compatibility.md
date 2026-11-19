# Codex CLI compatibility

Codex GUI communicates with the installed `codex app-server` process over its newline-delimited JSON protocol. The app-server protocol is experimental, so compatibility is based on tested CLI versions rather than a promise that every newer release will keep the same methods and fields.

## Current policy

- **Tested baseline:** Codex CLI 0.153.2.
- **Older versions:** rejected by the app's version check because they are below the supported protocol baseline.
- **Newer versions:** accepted by the current version check, but unverified until the compatibility procedure below passes. Their experimental protocol may have changed.

The app sends `experimentalApi: true` in `initialize` because it uses methods and fields marked experimental by the installed protocol. This is a client opt-in. It does not mean the server negotiated or guaranteed support for every experimental method the app uses.

Queue ownership and fallback follow [architecture](architecture.md#ownership-and-recovery).

Backend diagnostic redaction is pattern-based, so unnamed secrets, unusual encodings and truncated values can remain visible. Review reports before sharing them. Buffer limits and recognized patterns belong to [BackendDiagnostics](../Sources/CodexGUI/CodexClient/Diagnostics/BackendDiagnostics.swift).

## Verifying a CLI upgrade

Identify the executable selected by [AppKit executable selection](../Sources/CodexGUI/CodexClient/AppServer/AppServer+Executable.swift) or [desktop executable discovery](../desktop/core/src/codex/executable.rs). The shell's `codex` may resolve differently. Use that selected executable for the version and schema commands below.

The Tauri core takes an explicit absolute override, then `CODEX_EXECUTABLE`, then the launcher's `PATH` and known installation directories. An invalid override is reported so configuration does not silently pick another installation. The version probe uses the resolved path and includes its directory on the child `PATH` for package-manager shims.

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

## Voice chat

Voice chat uses V3 WebRTC with ChatGPT sign-in on the built-in OpenAI provider. API-key and bearer-token providers can use V3 WebSocket. If WebRTC fails during startup, the GUI can retry via WebSocket on the same thread when the credential check succeeds. Once a WebRTC start has been submitted, the retry waits for the server to confirm that the prior session closed. The provider confirms access when a session starts. After a live call drops, Reconnect starts a new session on the original thread with the same voice. The transcript belongs to the thread across both sessions.

Voice Settings uses the V3 catalog. The Voice sheet groups voices by known languages and writes the user-level default on Done. Cancel discards the pending choice. Choosing a voice in the sheet generates a short sample when the provider credentials required by [Read Aloud](#transcript-speech-and-result-feedback) are available. Workspace configuration can override the user default. Read the effective workspace choice at call startup so a loaded thread cannot reuse an earlier voice override. See the [voice adapter](../Sources/CodexGUI/CodexClient/AppServer/AppServer+VoiceChat.swift) for the session contract.

New voice threads use paginated history. Voice history follows the loaded turn window as the user scrolls back. Once ordinary turn pagination is exhausted, restore the remaining speech, including in voice-only chats. An existing chat keeps its history format. With legacy history, CodexGUI reads live transcript events and displays saved speech from the thread’s ordinary history.

Client audio is sent to the configured realtime provider while the microphone is active. The speakers control affects local playback. Speech can delegate work in the originating checkout using the coding model and permissions captured at call creation. Confirm microphone permission, audible duplex operation, a coding handoff, and chat switching on a live provider before claiming native parity.

## Transcript speech and result feedback

Read Aloud requires V3 realtime standalone speech and API-key or bearer-token credentials for the configured provider. ChatGPT sign-in alone leaves the action disabled, and a successful voice-list request can still be followed by a synthesis authorization failure. Playback uses the configured provider for the entire session, with no system voice fallback. See the [speech adapter](../Sources/CodexGUI/CodexClient/AppServer/AppServer+ReadAloud.swift) for admission and wire handling.

Result feedback honors `feedback.enabled`. Reconnect after changing backend credentials or feedback policy to refresh cached eligibility. See [transcript action behavior](architecture.md#presentation) and [native and live acceptance](validation.md#native-and-live-acceptance).

## Protocol lifecycle safeguards

JSONL framing must split on byte LF (`0x0A`), since Unicode line separators may occur inside JSON strings. Resolve unsupported interactive requests with the appropriate error, decline or cancellation response and visible feedback. Preserve method-specific acknowledgement/completion handling and events arriving before responses. Mutation uncertainty follows [recovery](architecture.md#ownership-and-recovery); composer-specific distinctions belong to [slash commands](slash-commands.md#lifecycle). Inspect [interaction handling](../Sources/CodexGUI/CodexClient/AppServer/AppServer+Interactions.swift) and [notifications](../Sources/CodexGUI/CodexClient/AppServer/AppServer+Notifications.swift) for concrete wire behavior.
