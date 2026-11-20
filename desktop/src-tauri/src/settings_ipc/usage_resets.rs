use codex_gui_core::{
    codex::{BrowseError, UsageResetOutcome},
    ipc::RedeemUsageReset,
};

use super::*;

#[tauri::command]
pub async fn redeem_settings_reset(
    window: WebviewWindow,
    settings: State<'_, SettingsIpc>,
    project: State<'_, ProjectIpc>,
    update: RedeemUsageReset,
) -> Result<SettingsView, IpcError> {
    authorize_view(&window)?;
    let session = update.selection.session;
    let (request, mut client, captured) = settings.mutation(&update.selection, |snapshot| {
        snapshot.account_id.is_some()
            && snapshot
                .reset_candidates
                .iter()
                .any(|credit| credit.offer.id == update.credit_id)
    })?;
    let account = captured
        .account_id
        .as_deref()
        .ok_or(IpcError::StaleSelection)?;
    let candidate = captured
        .reset_candidates
        .iter()
        .find(|credit| credit.offer.id == update.credit_id)
        .ok_or(IpcError::StaleSelection)?;
    let fresh = SettingsAuthority::read(&client).await?;
    let browser = CodexBrowser::new(client.clone());
    let limits = browser
        .settings_rate_limits(TIMEOUT)
        .await
        .map_err(report)?;
    if fresh != captured.authority
        || limits.account_id.as_deref() != Some(account)
        || !limits
            .reset_candidates()
            .iter()
            .any(|fresh| fresh.key == candidate.key)
    {
        return read_settings_view(
            &window,
            &settings,
            session,
            request,
            client,
            Some(captured.authority),
        )
        .await;
    }
    authorize_view(&window)?;
    let navigation = project
        .navigation
        .get()
        .ok_or(IpcError::ProjectUnavailable)?;
    let store = navigation.attachment_store();
    let attempt = Uuid::new_v4();
    let reserved = {
        let mut selected = settings.selected.lock().expect("settings lock poisoned");
        match_session(&mut selected, session, request)?;
        store
            .reserve_usage_reset(account, &candidate.key, attempt)
            .map_err(report)?
    };
    if reserved {
        let result = browser
            .redeem_usage_reset(update.credit_id.as_deref(), attempt, TIMEOUT)
            .await;
        let retryable = matches!(
            &result,
            Ok(UsageResetOutcome::NothingToReset | UsageResetOutcome::NoCredit)
        ) || matches!(&result, Err(BrowseError::Request(error)) if error.is_unsent());
        if retryable {
            store
                .release_usage_reset(account, &candidate.key, attempt)
                .map_err(report)?;
        }
        if let Err(error) = result {
            eprintln!("{error}");
            settings.retire_backend(session, request)?;
            client =
                settings.install(session, request, SettingsBackend::connect(&window).await?)?;
        }
    }
    read_settings_view(
        &window,
        &settings,
        session,
        request,
        client,
        Some(captured.authority),
    )
    .await
}
