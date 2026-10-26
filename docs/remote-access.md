# Remote access

Remote access uses the host Mac's Codex authentication, files, tools and execution permissions. The relay requires ChatGPT authentication; API-key authentication is unsupported. This optional experimental integration targets CLI 0.163.0; the general tested baseline belongs to [CLI compatibility](cli-compatibility.md#current-policy).

## Host lifetime

The source workspace's private app-server is the remote host, including while a managed task checkout is selected. Enablement is ephemeral at the server and persisted locally by the GUI, avoiding changes to Codex's global remote-control configuration. Reconnection restores that local choice. Separate managed-task app-servers are not enabled by it.

Quitting or reconnecting interrupts remote availability until the host connection returns. The Mac must remain awake and online; the GUI does not manage a background daemon. Leaving Connections stops its presentation polling without disabling the host. Keep this Mac awake applies only while connected on AC power.

## Setup and device management

1. Open Settings → Connections → Control this Mac and enable Allow connections.
2. Choose Add, then use Phone to scan the QR code or Computer to copy the manual code. Use the same account and workspace on the paired device.
3. Use Refresh to inspect devices and Revoke access to remove a captured device authorization.

An enable response may still be connecting. Pairing and device-list reads do not prove the host is online. Read failures must not be treated as mutation failures or cause enablement, pairing or revocation to be replayed. Pairing credentials remain transient and must be retired on expiry, claim, disconnection or dismissal.

## Connection errors

The relay permits one online app-server for a shared Codex installation. Simultaneously hosting from ChatGPT and this GUI can return `409 Conflict` with `Remote app server already online`. Disable remote access in the other app, then disable and re-enable it here. A previously paired device may remain listed during that conflict.

An inherited `RUST_LOG` can suppress the GUI's default relay diagnostics. Inspect [subprocess logging configuration](../Sources/CodexGUI/CodexClient/AppServer/AppServer+Environment.swift) when host status and diagnostics disagree. Review diagnostic output before sharing it under the [diagnostics guidance](cli-compatibility.md#current-policy).

## Ownership and validation

Apply [asynchronous ownership and recovery](architecture.md#ownership-and-recovery) to host, pairing and device requests. Remote status notifications must take precedence over older reads; environment changes invalidate device identities and pairing state. Local composer choices must survive unrelated settings notifications and stale resume snapshots, while corresponding authoritative backend changes may supersede them.

Inspect the [remote reducer](../Sources/CodexGUI/Application/Reducers/RemoteAccess/), [wire requests](../Sources/CodexGUI/CodexClient/AppServer/AppServer+RemoteAccess.swift) and [native feature](../Sources/CodexGUI/Features/RemoteAccess/) for current implementation.

Validate discovery, project catalogs, active-turn sharing and approval recovery with an authenticated phone before claiming mobile parity. Follow [live acceptance](validation.md#native-and-live-acceptance); successful host setup alone does not establish those behaviors.
