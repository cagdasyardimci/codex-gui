# Remote access

Remote access uses the host's Codex authentication, files, tools and execution permissions. Sign in with ChatGPT to use the relay. This experimental integration targets CLI 0.163.0. See [CLI compatibility](cli-compatibility.md#current-policy) for the general tested baseline.

## Host lifetime

The source workspace's private app-server is the remote host, including while a managed task checkout is selected. Enablement is ephemeral at the server and persisted locally by the GUI, avoiding changes to Codex's global remote-control configuration. Reconnection restores that local choice. Separate managed-task app-servers are not enabled by it.

Quitting or reconnecting interrupts remote availability until the host connection returns. Keep the desktop app open and online. Leaving Connections closes its pairing presentation and leaves the host running. Keep Computer Awake applies while connected on external power.

## Setup and device management

1. In Tauri open the source workspace, choose Settings → Connections, and turn on **Allow Connections**. In AppKit use **Control this Mac** on the Connections page.
2. Choose **Add Device**. Scan the QR code from **Phone**, or choose **Computer** and copy the manual code. Use the same ChatGPT account on the paired device.
3. Choose **Refresh Devices** to inspect the current list. Use **Manage** and **Revoke Access** for the device you want to remove.

An enable response may still be connecting. Pairing and device-list reads do not prove the host is online. Read failures must not be treated as mutation failures or cause enablement, pairing or revocation to be replayed. Pairing credentials remain transient and must be retired on expiry, claim, disconnection or dismissal.

## Connection errors

The relay permits one online app-server for a shared Codex installation. Simultaneously hosting from ChatGPT and this GUI can return `409 Conflict` with `Remote app server already online`. Disable remote access in the other app, then disable and re-enable it here. A previously paired device may remain listed during that conflict.

An inherited `RUST_LOG` can suppress the GUI's default relay diagnostics. Inspect [subprocess logging configuration](../Sources/CodexGUI/CodexClient/AppServer/AppServer+Environment.swift) when host status and diagnostics disagree. Review diagnostic output before sharing it under the [diagnostics guidance](cli-compatibility.md#current-policy).

## Ownership and validation

Apply [asynchronous ownership and recovery](architecture.md#ownership-and-recovery) to host, pairing and device requests. Remote status notifications must take precedence over older reads; environment changes invalidate device identities and pairing state. Local composer choices must survive unrelated settings notifications and stale resume snapshots, while corresponding authoritative backend changes may supersede them.

See the [Tauri relay host](../desktop/src-tauri/src/navigation/relay.rs), [device ownership](../desktop/src-tauri/src/relay_ipc/devices.rs), and the [Swift reference reducer](../Sources/CodexGUI/Application/Reducers/RemoteAccess/) for the ownership rules in each edition.

Validate discovery, project catalogs, active-turn sharing and approval recovery with an authenticated phone before claiming mobile parity. Follow [live acceptance](validation.md#native-and-live-acceptance); successful host setup alone does not establish those behaviors.
