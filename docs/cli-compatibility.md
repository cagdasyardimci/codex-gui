# Codex CLI compatibility

Codex GUI communicates with the installed `codex app-server` process over its
newline-delimited JSON protocol. The app-server protocol is experimental, so
compatibility is based on tested CLI versions rather than a promise that every
newer release will keep the same methods and fields.

## Current policy

- **Tested baseline:** Codex CLI 0.153.2.
- **Older versions:** rejected by the app's version check because they are below
  the supported protocol baseline.
- **Newer versions:** accepted by the current version check, but unverified
  until the compatibility procedure below passes. Their experimental protocol
  may have changed.

The app sends `experimentalApi: true` in `initialize` because it uses methods
and fields marked experimental by the installed protocol. This is a client
opt-in. It does not mean the server negotiated or guaranteed support for every
experimental method the app uses.

Backend details stay in memory for the current process connection and are
limited to the latest 8 KiB of stderr. The display redacts common API-key and
token forms, including named credential assignments, Bearer values, and
`sk-`-prefixed keys. Redaction is pattern-based and cannot identify every
possible secret format. Quoted assignment values can contain spaces, but
unnamed secrets, unquoted multi-word values, and truncated or unusual encodings
may remain visible. Review the report before copying or sharing it.

Conversation management uses `thread/list` with its `archived` filter,
`thread/name/set`, `thread/archive`, and `thread/unarchive`. Their request shapes
were checked against the locally generated 0.153.2 schema; integration fixtures
check the wire requests and opaque-cursor pagination. Search filters titles and
previews in the loaded project list. It does not use the experimental full-text
`thread/search` method. Unsupported management requests surface their backend
error in the app.

CLI version probing has a 10-second deadline and runs away from the main actor.
A stalled or continuously writing `--version` child cannot leave the interface
waiting indefinitely.

## Verifying a CLI upgrade

For each CLI version proposed as supported:

1. Record the exact `codex --version` output.
2. Generate that version's JSON schema with
   `codex app-server generate-json-schema --experimental --out <temporary-directory>`.
3. Check every request, notification, server request, and response shape used
   by the app against the generated schema. Pay particular attention to
   permissions, command and file approvals, questions, turn events, and thread
   history methods.
4. Run the mock protocol and state suites, including timeout, disconnect,
   approval, and recovery cases.
5. Run read-only live checks for `initialize`, account status, model listing,
   and thread listing.
6. Complete the disposable-repository live acceptance workflow and record
   which criteria were observed.

Update the tested-version record only after these checks pass. A successful
handshake or generated schema alone does not establish full compatibility.
