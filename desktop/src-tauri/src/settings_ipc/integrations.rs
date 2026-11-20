use codex_gui_core::ipc::{
    ChangeSettingsIntegration, McpSettingsForm, SettingsCatalog, SettingsCatalogKind,
    SettingsIntegrationAction, SettingsWriteOutcome,
};

use super::*;

impl SettingsIpc {
    fn integration_read(
        &self,
        selection: &SettingsSelection,
    ) -> Result<
        (
            Uuid,
            AppServerClient,
            SettingsAuthority,
            Option<CheckoutIdentity>,
        ),
        IpcError,
    > {
        let selected = self.selected.lock().expect("settings lock poisoned");
        let session = selected
            .as_ref()
            .filter(|session| session.id == selection.session)
            .ok_or(IpcError::StaleSelection)?;
        let snapshot = session
            .snapshot
            .as_ref()
            .filter(|snapshot| snapshot.revision == selection.revision)
            .ok_or(IpcError::StaleSelection)?;
        let backend = session.backend.as_ref().ok_or(IpcError::StaleSelection)?;
        Ok((
            session.request,
            backend.client.clone(),
            snapshot.authority.clone(),
            snapshot.home.clone(),
        ))
    }
}

#[tauri::command]
pub async fn read_settings_catalog(
    window: WebviewWindow,
    settings: State<'_, SettingsIpc>,
    selection: SettingsSelection,
    kind: SettingsCatalogKind,
) -> Result<SettingsCatalog, IpcError> {
    authorize_view(&window)?;
    let (request, client, authority, home) = settings.integration_read(&selection)?;
    let catalog = CodexBrowser::new(client.clone())
        .settings_integration_catalog(kind, home.as_ref(), TIMEOUT)
        .await
        .map_err(report)?;
    if SettingsAuthority::read(&client).await? != authority {
        return Err(IpcError::StaleSelection);
    }
    authorize_view(&window)?;
    let result = catalog.view(kind, &authority.configuration.integrations);
    let mut selected = settings.selected.lock().expect("settings lock poisoned");
    match_session(&mut selected, selection.session, request)?
        .snapshot
        .as_mut()
        .filter(|snapshot| snapshot.revision == selection.revision)
        .ok_or(IpcError::StaleSelection)?
        .catalogs
        .replace(catalog);
    Ok(result)
}

#[tauri::command]
pub async fn read_settings_mcp(
    window: WebviewWindow,
    settings: State<'_, SettingsIpc>,
    selection: SettingsSelection,
    name: String,
) -> Result<McpSettingsForm, IpcError> {
    authorize_view(&window)?;
    let (request, client, authority, _) = settings.integration_read(&selection)?;
    let form = authority
        .configuration
        .integrations
        .mcp_form(&name)
        .ok_or(IpcError::StaleSelection)?;
    if SettingsAuthority::read(&client).await? != authority {
        return Err(IpcError::StaleSelection);
    }
    authorize_view(&window)?;
    settings.validate_request(selection.session, request)?;
    Ok(form)
}

#[tauri::command]
pub async fn change_settings_integration(
    window: WebviewWindow,
    settings: State<'_, SettingsIpc>,
    project: State<'_, ProjectIpc>,
    update: ChangeSettingsIntegration,
) -> Result<SettingsWriteOutcome, IpcError> {
    authorize_view(&window)?;
    let session = update.selection.session;
    let (request, client, captured) = settings.mutation(&update.selection, |snapshot| {
        snapshot.integration_owner == update.owner
    })?;
    let configuration = &captured.authority.configuration;
    let browser = CodexBrowser::new(client.clone());
    let operation = configuration
        .integrations
        .operation(&update.action, &captured.catalogs);
    let catalog_kind = IntegrationCatalogs::for_action(&update.action);
    let catalog_matches = if let Some(kind) = catalog_kind {
        browser
            .settings_integration_catalog(kind, captured.home.as_ref(), TIMEOUT)
            .await
            .is_ok_and(|catalog| captured.catalogs.matches(kind, &catalog))
    } else {
        true
    };
    let remote_catalog = matches!(catalog_kind, Some(SettingsCatalogKind::Plugins))
        || matches!(
            update.action,
            SettingsIntegrationAction::AddMarketplace { .. }
        );
    let same_account = if let Some(account) = &captured.account_id
        && remote_catalog
    {
        browser
            .settings_rate_limits(TIMEOUT)
            .await
            .is_ok_and(|limits| limits.account_id.as_ref() == Some(account))
    } else {
        true
    };
    let fresh = SettingsAuthority::read(&client).await?;
    let mut confirmed = false;
    let mut reconnect = false;
    if let Some(operation) = operation
        && fresh == captured.authority
        && catalog_matches
        && same_account
    {
        authorize_view(&window)?;
        settings.validate_request(session, request)?;
        let config_changed = operation.changes_configuration();
        let result = browser
            .change_settings_integration(configuration, operation, TIMEOUT)
            .await;
        if !matches!(
            &update.action,
            SettingsIntegrationAction::AuthenticateMcp { .. }
        ) {
            project
                .state
                .lock()
                .expect("workspace state lock poisoned")
                .composer_catalog = None;
            if config_changed
                && result.is_ok()
                && let Some(navigation) = project.navigation.get()
                && let Err(error) = navigation.settings_committed().await
            {
                eprintln!("{error:?}");
            }
            reconnect = true;
        }
        confirmed = match result {
            Ok(Some(url)) => {
                settings.validate_request(session, request)?;
                if *window.state::<crate::fixture::Verification>()
                    == crate::fixture::Verification::Settings
                {
                    true
                } else {
                    open::that_detached(url.as_str()).is_ok()
                }
            }
            Ok(None) => true,
            Err(error) => {
                eprintln!("{error}");
                reconnect = true;
                false
            }
        };
    }
    let client = if reconnect {
        settings.retire_backend(session, request)?;
        settings.install(session, request, SettingsBackend::connect(&window).await?)?
    } else {
        client
    };
    let previous = if reconnect {
        None
    } else {
        Some(captured.authority)
    };
    let view = read_settings_view(&window, &settings, session, request, client, previous).await?;
    Ok(SettingsWriteOutcome { view, confirmed })
}
