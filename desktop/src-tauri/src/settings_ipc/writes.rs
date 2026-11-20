use codex_gui_core::ipc::{SetEffortVisibility, SettingsWriteOutcome, WriteSettingsValue};

use super::*;

#[tauri::command]
pub async fn write_settings(
    window: WebviewWindow,
    settings: State<'_, SettingsIpc>,
    project: State<'_, ProjectIpc>,
    update: WriteSettingsValue,
) -> Result<SettingsWriteOutcome, IpcError> {
    authorize_view(&window)?;
    let session = update.selection.session;
    let (request, client, captured) = settings.mutation(&update.selection, |snapshot| {
        snapshot
            .authority
            .configuration
            .accepts(&update.key, &update.value)
    })?;
    if SettingsAuthority::read(&client).await? != captured.authority {
        settings.retire_backend(session, request)?;
        return Err(IpcError::StaleSelection);
    }
    authorize_view(&window)?;
    settings.validate_request(session, request)?;
    let browser = CodexBrowser::new(client);
    let result = browser
        .write_settings_value(
            &captured.authority.configuration,
            &update.key,
            update.value,
            TIMEOUT,
        )
        .await;
    let confirmed = result.is_ok();
    if let Err(error) = result {
        eprintln!("{error}");
    } else if let Some(navigation) = project.navigation.get()
        && let Err(error) = navigation.settings_committed().await
    {
        eprintln!("{error:?}");
    }
    settings.retire_backend(session, request)?;
    let client = settings.install(session, request, SettingsBackend::connect(&window).await?)?;
    let view = read_settings_view(&window, &settings, session, request, client, None).await?;
    Ok(SettingsWriteOutcome { view, confirmed })
}

#[tauri::command]
pub async fn delete_settings_memories(
    window: WebviewWindow,
    settings: State<'_, SettingsIpc>,
    selection: SettingsSelection,
) -> Result<SettingsView, IpcError> {
    authorize_view(&window)?;
    let session = selection.session;
    let (request, client, captured) = settings.mutation(&selection, |snapshot| {
        snapshot.authority.configuration.memories.is_some()
    })?;
    if SettingsAuthority::read(&client).await? != captured.authority {
        settings.retire_backend(session, request)?;
        return Err(IpcError::StaleSelection);
    }
    authorize_view(&window)?;
    settings.validate_request(session, request)?;
    let result = CodexBrowser::new(client.clone())
        .reset_settings_memories(TIMEOUT)
        .await;
    if let Err(error) = result {
        settings.retire_backend(session, request)?;
        return Err(report(error));
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

#[tauri::command]
pub async fn set_effort_visibility(
    window: WebviewWindow,
    settings: State<'_, SettingsIpc>,
    project: State<'_, ProjectIpc>,
    update: SetEffortVisibility,
) -> Result<SettingsView, IpcError> {
    authorize_view(&window)?;
    let session = update.selection.session;
    let (request, client, captured) = settings.mutation(&update.selection, |snapshot| {
        snapshot.efforts.contains(&update.effort)
            && !REQUIRED_EFFORTS.contains(&update.effort.as_str())
    })?;
    if SettingsAuthority::read(&client).await? != captured.authority
        || !catalog_efforts(&CodexBrowser::new(client.clone()))
            .await
            .contains(&update.effort)
    {
        return Err(IpcError::StaleSelection);
    }
    authorize_view(&window)?;
    let navigation = project
        .navigation
        .get()
        .ok_or(IpcError::ProjectUnavailable)?;
    {
        let mut selected = settings.selected.lock().expect("settings lock poisoned");
        match_session(&mut selected, session, request)?;
        navigation
            .attachment_store()
            .set_effort_visibility(&update.effort, update.visible)
            .map_err(report)?;
    }
    navigation.reasoning_visibility_changed().await?;
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
