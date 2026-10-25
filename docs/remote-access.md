# Remote access

Remote Access in Settings manages Codex's remote-control relay for the main window's source
app-server connection. The host remains the same when the user selects a managed task checkout.
Remote access uses the host's Codex authentication, files, tools, and execution permissions.
ChatGPT authentication is required; API-key authentication is not supported by the relay.

## Host lifetime

The GUI retains its existing private `codex app-server --stdio` connection. Enabling and disabling
remote access sends `ephemeral: true`: the choice applies to that running server without changing
Codex's global remote-control configuration. The source workspace stores the user's enablement
choice in the `local.codexgui.appkit` preferences domain and re-enables remote access after its next
successful app-server connection. This setting is shared by bundled and direct SwiftPM launches;
an explicit test preferences suite remains isolated. A missing shared setting is migrated from
the launching process's existing preference when available.
Disabling access clears that choice. Quitting or reconnecting the GUI terminates the current server
and interrupts remote availability until the new connection is ready. The Mac must stay awake and
online. Background daemon management is not part of this integration. Each managed task checkout
still has its own app-server; enabling the main host does not enable or share those separate active
sessions.

Remote access is an optional experimental protocol capability implemented against CLI 0.163.0.
The application's general tested CLI baseline remains defined by [CLI compatibility](cli-compatibility.md).
A server that rejects the remote-control methods reports its error in the Remote Access window;
successful initialization alone does not establish remote-control availability.

## Setup and device management

Open Settings > Backend > Remote Access, then enable access. An enable response can report
`connecting`; only `connected` enables Pair iPhone. Remote status notifications update the panel,
and the visible panel refreshes status and devices every five seconds. Disabling access can cancel a pending refresh or
pairing operation. Refreshing does not replay
enablement, pairing, or revocation mutations.

Pair iPhone requests a manual code. Enter it when adding the computer in ChatGPT on iPhone, using
the same account and workspace. Pairing codes and their expiration remain in memory. Expiration
uses the server's Unix timestamp in seconds. The panel checks expiry each second, polls whether
the code was claimed, and clears it when claimed, expired, disconnected, or closed. Closing the
window also invalidates a pending pairing result. Pairing codes and remote-control tokens are
redacted when recognizable named fields occur in backend diagnostics or remote-access errors.

The device list follows pagination with cursor-cycle detection and bounded page and row totals. Removing a
device captures its environment and client identifiers and requires that they still match the
current host. A confirmed revocation removes that row without depending on a subsequent read.
Device-list and pairing-status read failures remain visible while preserving successfully read
host status. They do not establish that a preceding mutation failed or should be resent.

## Connection errors

The relay permits one online app-server for the shared Codex installation. Running ChatGPT's
remote host and this GUI's host at the same time can return `409 Conflict` with
`Remote app server already online`. Disable remote access in the other app, then disable and
re-enable it here. An existing paired iPhone can appear in the shared device list even while this
GUI's host is unable to connect; the device list alone does not prove this host is online.

The window identifies that conflict when its backend log is available. Backend Details opens
the main host's diagnostics, refreshed after remote operations. By default, the GUI enables relay
logging with `RUST_LOG=error,codex_app_server_transport::transport::remote_control=info` for its
subprocess. An explicitly inherited `RUST_LOG` is preserved and may suppress those diagnostics.
The GUI does not disable another app's host automatically.

## Ownership and validation

Remote-access state belongs to `WorkspaceModel.remoteAccess`. Only the source workspace restores
and persists the local enablement choice; managed task app-servers do not auto-enable. The reducer
validates workspace, connection generation, and pending request identity. Status notifications
advance a revision so a late read cannot replace newer status. Environment changes clear pairing
and device state. Views
send commands through `WorkspaceStoreInputs`; the effect runner owns backend work.

The existing conversation and approval reducers retain their ownership and uncertain-outcome
contracts. Remote setup does not prove that mobile chat discovery, project catalogs, active-turn
sharing, or approval recovery work with every mobile app version. Validate those behaviors with an
authenticated iPhone before claiming complete mobile parity. Controlled fixtures establish only
their asserted wire, state, and AppKit behaviors; see [validation](validation.md#native-and-live-acceptance).
