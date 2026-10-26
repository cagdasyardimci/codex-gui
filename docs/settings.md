# Settings

This guide owns configuration semantics and capability boundaries. Page routes, controls, field mappings and presentation values are defined in [Features/Settings](../Sources/CodexGUI/Features/Settings/). Shared presentation policy belongs to [interface styling](interface-styling.md).

## Configuration ownership

Settings uses a presentation-scoped backend connection so user configuration work does not acquire workspace turn ownership. Order reads and saves, reject results after the presentation or connection is retired, and reread effective configuration and managed requirements after a confirmed save. Do not automatically retry failed or uncertain mutations. Connections management retains the separate [remote host lifetime](remote-access.md#host-lifetime).

Write against the active user layer and its version when available. Replace origin maps as a table: dots in site names must not become configuration path separators. Feature availability comes from the advertised catalog; missing config keys do not establish disabled features, and catalog failures must not prevent unrelated configuration work. Managed requirements take precedence over editable defaults.

Confirmed permission and speed saves also update GUI submission preferences. Composer overrides and running turns follow [submission capture](architecture.md#state-transitions). Replacing a custom approval object with a supported choice must precede editing its sandbox defaults. Reasoning visibility preferences filter supported options without changing the chat's selected effort.

## Capability boundaries

Browser configuration values do not implement native browser approval services. Voice changes the advertised Codex realtime default rather than ChatGPT account voice or audio capture. Account profile changes, purchases, hosted preferences and training controls require backend actions before being presented as working mutations.

Archive search must cover all loaded metadata, independently of row pagination. Destructive actions retain captured IDs and revalidate current membership before mutation. Usage analytics and balances must use reported values; available reset credits cannot establish complete reset history. Reset consumption requires confirmation and fresh eligibility, identity and expiration checks.

Editors of external configuration files must preserve unsaved drafts on conflicts and require an explicit decision before replacing them. Catalog mutations must invalidate affected cached reads without silently discarding failed form drafts.

## Desktop notifications

Notification timing, alert categories and sound are local preferences; macOS authorization is independent. Continue observing transitions while notifications are disabled so enabling them cannot replay old alerts. Recheck preferences after authorization and before foreground presentation.

Custom notification audio must meet UserNotifications format and duration requirements and be published atomically; failed or canceled imports preserve the saved choice. Sound options, migration and import mechanics live in [TaskNotificationSound](../Sources/CodexGUI/App/Notifications/TaskNotificationSound.swift). Stable application identity and permission setup follow [signing setup](../README.md#signing-setup). Audible delivery and OS authorization require [live acceptance](validation.md#native-and-live-acceptance).
