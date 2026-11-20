use std::{sync::Mutex, time::Duration};

use codex_gui_core::{
    codex::{
        Account, AccountSnapshot, AppServerClient, AppServerConnection, ClientInfo, CodexBrowser,
        CodexExecutable, EffectiveConfiguration, SettingsRateLimits,
    },
    identity::{CheckoutSessionId, ConnectionGeneration, ConnectionIdentity, WorkspaceIdentity},
    ipc::{IpcError, SettingsAccountView, SettingsSelection, SettingsView},
};
use tauri::{State, WebviewWindow};
use tokio::sync::watch;
use uuid::Uuid;

use crate::project_ipc::{ProjectIpc, authorize_view};

const TIMEOUT: Duration = Duration::from_secs(8);

#[derive(Default)]
pub struct SettingsIpc {
    selected: Mutex<Option<Session>>,
}

struct Session {
    id: Uuid,
    request: Uuid,
    backend: Option<SettingsBackend>,
    snapshot: Option<Published>,
    last_authority: Option<SettingsAuthority>,
}

struct SettingsBackend {
    client: AppServerClient,
    _lifetime: watch::Sender<()>,
}

#[derive(Clone, PartialEq)]
struct SettingsAuthority {
    account: AccountSnapshot,
    configuration: EffectiveConfiguration,
}

struct Published {
    authority: SettingsAuthority,
    account_id: Option<String>,
    sign_out: bool,
    revision: Uuid,
}

impl SettingsIpc {
    fn request(
        &self,
        session: Uuid,
    ) -> Result<(Uuid, Option<AppServerClient>, Option<SettingsAuthority>), IpcError> {
        let mut selected = self.selected.lock().expect("settings lock poisoned");
        let view = selected
            .as_mut()
            .filter(|view| view.id == session)
            .ok_or(IpcError::StaleSelection)?;
        let client = view.backend.as_ref().map(|backend| backend.client.clone());
        view.snapshot = None;
        let previous = view.last_authority.clone();
        view.request = Uuid::new_v4();
        Ok((view.request, client, previous))
    }

    fn install(
        &self,
        session: Uuid,
        request: Uuid,
        backend: SettingsBackend,
    ) -> Result<AppServerClient, IpcError> {
        let client = backend.client.clone();
        let mut selected = self.selected.lock().expect("settings lock poisoned");
        let view = match_session(&mut selected, session, request)?;
        view.backend = Some(backend);
        Ok(client)
    }

    fn retire_backend(&self, session: Uuid, request: Uuid) -> Result<(), IpcError> {
        let mut selected = self.selected.lock().expect("settings lock poisoned");
        match_session(&mut selected, session, request)?.backend = None;
        Ok(())
    }

    fn publish(&self, session: Uuid, request: Uuid, snapshot: Published) -> Result<(), IpcError> {
        let mut selected = self.selected.lock().expect("settings lock poisoned");
        let view = match_session(&mut selected, session, request)?;
        view.last_authority = Some(snapshot.authority.clone());
        view.snapshot = Some(snapshot);
        Ok(())
    }
}

fn match_session(
    selected: &mut Option<Session>,
    session: Uuid,
    request: Uuid,
) -> Result<&mut Session, IpcError> {
    selected
        .as_mut()
        .filter(|view| view.id == session && view.request == request)
        .ok_or(IpcError::StaleSelection)
}

#[tauri::command]
pub async fn open_settings(
    window: WebviewWindow,
    settings: State<'_, SettingsIpc>,
    session: Uuid,
) -> Result<SettingsView, IpcError> {
    authorize_view(&window)?;
    let request = Uuid::new_v4();
    {
        let mut selected = settings.selected.lock().expect("settings lock poisoned");
        *selected = Some(Session {
            id: session,
            request,
            backend: None,
            snapshot: None,
            last_authority: None,
        });
    }
    let backend = SettingsBackend::connect().await?;
    let client = settings.install(session, request, backend)?;
    read_settings_view(&window, &settings, session, request, client, None).await
}

#[tauri::command]
pub async fn refresh_settings(
    window: WebviewWindow,
    settings: State<'_, SettingsIpc>,
    session: Uuid,
) -> Result<SettingsView, IpcError> {
    authorize_view(&window)?;
    let (request, client, previous) = settings.request(session)?;
    let client = match client {
        Some(client) => client,
        None => settings.install(session, request, SettingsBackend::connect().await?)?,
    };
    read_settings_view(&window, &settings, session, request, client, previous).await
}

#[tauri::command]
pub fn close_settings(
    window: WebviewWindow,
    settings: State<'_, SettingsIpc>,
    session: Uuid,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    let mut selected = settings.selected.lock().expect("settings lock poisoned");
    if selected.as_ref().is_some_and(|view| view.id == session) {
        *selected = None;
    }
    Ok(())
}

#[tauri::command]
pub async fn sign_out_settings(
    window: WebviewWindow,
    settings: State<'_, SettingsIpc>,
    project: State<'_, ProjectIpc>,
    selection: SettingsSelection,
) -> Result<SettingsView, IpcError> {
    authorize_view(&window)?;
    let session = selection.session;
    let request = Uuid::new_v4();
    let (client, expected, account_id) = {
        let mut selected = settings.selected.lock().expect("settings lock poisoned");
        let view = selected
            .as_mut()
            .filter(|view| view.id == session)
            .ok_or(IpcError::StaleSelection)?;
        let backend = view.backend.as_ref().ok_or(IpcError::StaleSelection)?;
        let snapshot = view
            .snapshot
            .as_ref()
            .filter(|snapshot| snapshot.revision == selection.revision && snapshot.sign_out)
            .ok_or(IpcError::StaleSelection)?;
        view.request = request;
        let expected = snapshot.authority.clone();
        let account_id = snapshot.account_id.clone();
        view.snapshot = None;
        (backend.client.clone(), expected, account_id)
    };
    let fresh = SettingsAuthority::read(&client).await?;
    let fresh_account = CodexBrowser::new(client.clone())
        .settings_rate_limits(TIMEOUT)
        .await
        .ok()
        .and_then(|rates| rates.account_id);
    if fresh != expected || fresh_account != account_id {
        settings.retire_backend(session, request)?;
        return Err(IpcError::StaleSelection);
    }
    {
        authorize_view(&window)?;
        let mut selected = settings.selected.lock().expect("settings lock poisoned");
        match_session(&mut selected, session, request)?;
    }
    let navigation = project
        .navigation
        .get()
        .ok_or(IpcError::ProjectUnavailable)?;
    navigation
        .sign_out_settings(client, expected.account)
        .await?;
    settings.retire_backend(session, request)?;
    let backend = SettingsBackend::connect().await?;
    let client = settings.install(session, request, backend)?;
    read_settings_view(&window, &settings, session, request, client, None).await
}

impl SettingsBackend {
    async fn connect() -> Result<Self, IpcError> {
        let executable = CodexExecutable::discover(None).map_err(report)?;
        let identity = ConnectionIdentity {
            workspace: WorkspaceIdentity {
                session: CheckoutSessionId(Uuid::new_v4()),
                checkout: None,
            },
            generation: ConnectionGeneration(1),
        };
        let mut connection = AppServerConnection::connect(
            &executable,
            identity,
            ClientInfo {
                name: "codex_gui_settings",
                title: "Codex GUI Settings",
                version: env!("CARGO_PKG_VERSION"),
            },
            TIMEOUT,
        )
        .await
        .map_err(report)?;
        let client = connection.client();
        let (lifetime, mut release) = watch::channel(());
        tauri::async_runtime::spawn(async move {
            loop {
                tokio::select! {
                    _ = release.changed() => break,
                    event = connection.next_event() => {
                        if event.is_none() { break; }
                    }
                }
            }
            if let Err(error) = connection.disconnect().await {
                eprintln!("{error}");
            }
        });
        Ok(Self {
            client,
            _lifetime: lifetime,
        })
    }
}

impl SettingsAuthority {
    async fn read(client: &AppServerClient) -> Result<Self, IpcError> {
        let browser = CodexBrowser::new(client.clone());
        let (account, configuration) = tokio::try_join!(
            browser.account(TIMEOUT),
            browser.settings_configuration(TIMEOUT)
        )
        .map_err(report)?;
        Ok(Self {
            account,
            configuration,
        })
    }

    fn account_view(&self, rates: Option<&SettingsRateLimits>) -> SettingsAccountView {
        let (email, plan) = match &self.account.account {
            Some(Account::Chatgpt { email, plan_type }) => (email.clone(), Some(plan_type.clone())),
            _ => (None, None),
        };
        let can_sign_out = email.as_ref().is_some_and(|email| !email.trim().is_empty())
            && self
                .configuration
                .provider
                .as_deref()
                .is_none_or(|provider| provider == "openai");
        SettingsAccountView {
            provider: self.configuration.provider.clone(),
            email,
            plan: rates.and_then(SettingsRateLimits::plan).or(plan),
            can_sign_out,
        }
    }
}

async fn read_settings_view(
    window: &WebviewWindow,
    settings: &SettingsIpc,
    session: Uuid,
    request: Uuid,
    mut client: AppServerClient,
    previous: Option<SettingsAuthority>,
) -> Result<SettingsView, IpcError> {
    let first = match SettingsAuthority::read(&client).await {
        Ok(authority) => authority,
        Err(error) => {
            settings.retire_backend(session, request)?;
            return Err(error);
        }
    };
    let authority = if previous.as_ref().is_some_and(|previous| previous != &first) {
        settings.retire_backend(session, request)?;
        client = settings.install(session, request, SettingsBackend::connect().await?)?;
        SettingsAuthority::read(&client).await?
    } else {
        first
    };
    let browser = CodexBrowser::new(client.clone());
    let (limits, daily) = if authority.account.account.is_some() {
        let (limits, daily) = tokio::join!(
            browser.settings_rate_limits(TIMEOUT),
            browser.settings_daily_usage(TIMEOUT)
        );
        (limits.ok(), daily.ok().flatten())
    } else {
        (None, None)
    };
    if SettingsAuthority::read(&client).await? != authority {
        settings.retire_backend(session, request)?;
        return Err(IpcError::StaleSelection);
    }
    authorize_view(window)?;
    let revision = Uuid::new_v4();
    let account_id = limits.as_ref().and_then(|rates| rates.account_id.clone());
    let view = SettingsView {
        revision,
        account: authority.account_view(limits.as_ref()),
        limits: limits.map_or_else(Vec::new, |rates| rates.windows()),
        daily_usage: daily,
        configuration: authority.configuration.entries.clone(),
    };
    settings.publish(
        session,
        request,
        Published {
            authority,
            account_id,
            sign_out: view.account.can_sign_out,
            revision,
        },
    )?;
    Ok(view)
}

fn report(error: impl std::fmt::Display) -> IpcError {
    eprintln!("{error}");
    IpcError::ProjectUnavailable
}
