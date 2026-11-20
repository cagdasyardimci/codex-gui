use std::{
    collections::{BTreeSet, HashSet},
    path::PathBuf,
    sync::Mutex,
    time::Duration,
};

use codex_gui_core::{
    checkout::CheckoutIdentity,
    codex::{
        Account, AccountSnapshot, AppServerClient, AppServerConnection, ClientInfo, CodexBrowser,
        CodexExecutable, EffectiveConfiguration, IntegrationCatalogs, ResetCandidate,
        SettingsRateLimits,
    },
    identity::{CheckoutSessionId, ConnectionGeneration, ConnectionIdentity, WorkspaceIdentity},
    ipc::{IpcError, SettingsAccountView, SettingsEffort, SettingsSelection, SettingsView},
    storage::attachments::reasoning_visibility::REQUIRED_EFFORTS,
};
use tauri::{Manager, State, WebviewWindow};
use tokio::sync::watch;
use uuid::Uuid;

use crate::project_ipc::{ProjectIpc, authorize_view};

const TIMEOUT: Duration = Duration::from_secs(8);
pub(crate) mod instructions;
pub(crate) mod integrations;
pub(crate) mod usage_resets;
pub(crate) mod writes;

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
    instructions: Option<instructions::InstructionsFile>,
    integration_owner: Option<(Uuid, IntegrationOwner)>,
}

struct SettingsBackend {
    client: AppServerClient,
    home: Option<CheckoutIdentity>,
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
    efforts: BTreeSet<String>,
    reset_candidates: Vec<ResetCandidate>,
    catalogs: IntegrationCatalogs,
    integration_owner: Uuid,
    home: Option<CheckoutIdentity>,
}

#[derive(PartialEq, Eq)]
struct IntegrationOwner {
    account: AccountSnapshot,
    account_id: Option<String>,
    provider: Option<String>,
    config_file: Option<PathBuf>,
    home: Option<(PathBuf, String)>,
}

impl SettingsIpc {
    fn mutation(
        &self,
        selection: &SettingsSelection,
        permitted: impl FnOnce(&Published) -> bool,
    ) -> Result<(Uuid, AppServerClient, Published), IpcError> {
        let mut selected = self.selected.lock().expect("settings lock poisoned");
        let view = selected
            .as_mut()
            .filter(|view| view.id == selection.session)
            .ok_or(IpcError::StaleSelection)?;
        let client = view
            .backend
            .as_ref()
            .ok_or(IpcError::StaleSelection)?
            .client
            .clone();
        if !view
            .snapshot
            .as_ref()
            .is_some_and(|snapshot| snapshot.revision == selection.revision && permitted(snapshot))
        {
            return Err(IpcError::StaleSelection);
        }
        let snapshot = view.snapshot.take().expect("checked Settings snapshot");
        view.request = Uuid::new_v4();
        Ok((view.request, client, snapshot))
    }

    fn validate_request(&self, session: Uuid, request: Uuid) -> Result<(), IpcError> {
        let mut selected = self.selected.lock().expect("settings lock poisoned");
        match_session(&mut selected, session, request).map(|_| ())
    }

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
        if view
            .instructions
            .as_ref()
            .is_some_and(|file| !file.matches_home(backend.home.as_ref()))
        {
            view.instructions = None;
        }
        view.backend = Some(backend);
        Ok(client)
    }

    fn retire_backend(&self, session: Uuid, request: Uuid) -> Result<(), IpcError> {
        let mut selected = self.selected.lock().expect("settings lock poisoned");
        let view = match_session(&mut selected, session, request)?;
        view.backend = None;
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
            instructions: None,
            integration_owner: None,
        });
    }
    let backend = SettingsBackend::connect(&window).await?;
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
        None => settings.install(session, request, SettingsBackend::connect(&window).await?)?,
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
    let (request, client, captured) =
        settings.mutation(&selection, |snapshot| snapshot.sign_out)?;
    let fresh = SettingsAuthority::read(&client).await?;
    let fresh_account = CodexBrowser::new(client.clone())
        .settings_rate_limits(TIMEOUT)
        .await
        .ok()
        .and_then(|rates| rates.account_id);
    if fresh != captured.authority || fresh_account != captured.account_id {
        settings.retire_backend(session, request)?;
        return Err(IpcError::StaleSelection);
    }
    authorize_view(&window)?;
    settings.validate_request(session, request)?;
    let navigation = project
        .navigation
        .get()
        .ok_or(IpcError::ProjectUnavailable)?;
    navigation
        .sign_out_settings(client, captured.authority.account)
        .await?;
    settings.retire_backend(session, request)?;
    let backend = SettingsBackend::connect(&window).await?;
    let client = settings.install(session, request, backend)?;
    read_settings_view(&window, &settings, session, request, client, None).await
}

impl SettingsBackend {
    async fn connect(window: &WebviewWindow) -> Result<Self, IpcError> {
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
        let expected = std::env::var_os("CODEX_HOME")
            .map(PathBuf::from)
            .or_else(|| {
                window
                    .path()
                    .home_dir()
                    .ok()
                    .map(|path| path.join(".codex"))
            });
        let reported = connection.initialization()["codexHome"]
            .as_str()
            .map(PathBuf::from);
        let home = expected
            .and_then(|path| CheckoutIdentity::capture(&path).ok())
            .filter(|home| {
                reported
                    .as_ref()
                    .is_none_or(|path| home.validate_reported(path).is_ok())
            });
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
            home,
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
        client = settings.install(session, request, SettingsBackend::connect(window).await?)?;
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
    let efforts = catalog_efforts(&browser).await;
    let project = window.state::<ProjectIpc>();
    let hidden = project
        .navigation
        .get()
        .map(|navigation| navigation.attachment_store().hidden_reasoning_efforts())
        .transpose()
        .map_err(report)?
        .unwrap_or_default();
    if SettingsAuthority::read(&client).await? != authority {
        settings.retire_backend(session, request)?;
        return Err(IpcError::StaleSelection);
    }
    authorize_view(window)?;
    let revision = Uuid::new_v4();
    let account_id = limits.as_ref().and_then(|rates| rates.account_id.clone());
    let (home, integration_owner) = {
        let mut selected = settings.selected.lock().expect("settings lock poisoned");
        let current = match_session(&mut selected, session, request)?;
        let home = current
            .backend
            .as_ref()
            .and_then(|backend| backend.home.as_ref());
        let owner = IntegrationOwner {
            account: authority.account.clone(),
            account_id: account_id.clone(),
            provider: authority.configuration.provider.clone(),
            config_file: authority.configuration.user_file().map(PathBuf::from),
            home: home.map(|home| (home.canonical_path().to_owned(), home.storage_key())),
        };
        let home = home.cloned();
        let id = current
            .integration_owner
            .as_ref()
            .filter(|(_, active)| active == &owner)
            .map(|(id, _)| *id)
            .unwrap_or_else(Uuid::new_v4);
        current.integration_owner = Some((id, owner));
        (home, id)
    };
    let reset_balance = limits.as_ref().and_then(SettingsRateLimits::reset_balance);
    let reset_candidates = match (&account_id, limits.as_ref(), project.navigation.get()) {
        (Some(account), Some(limits), Some(navigation)) => {
            let reserved = navigation
                .attachment_store()
                .reserved_usage_resets(account)
                .map_err(report)?;
            limits
                .reset_candidates()
                .into_iter()
                .filter(|candidate| !reserved.contains(&candidate.key))
                .collect()
        }
        _ => Vec::new(),
    };
    let view = SettingsView {
        revision,
        account: authority.account_view(limits.as_ref()),
        limits: limits.map_or_else(Vec::new, |rates| rates.windows()),
        daily_usage: daily,
        configuration: authority.configuration.entries.clone(),
        compression: authority.configuration.compression.clone(),
        network_access: authority.configuration.network_access.clone(),
        memories: authority.configuration.memories.clone(),
        instructions_available: home.is_some(),
        reset_balance,
        reset_offers: reset_candidates
            .iter()
            .map(|candidate| candidate.offer.clone())
            .collect(),
        integrations: authority.configuration.integrations.view(),
        integration_owner,
        efforts: efforts
            .iter()
            .map(|effort| SettingsEffort {
                effort: effort.clone(),
                visible: !hidden.contains(effort),
                required: REQUIRED_EFFORTS.contains(&effort.as_str()),
            })
            .collect(),
    };
    settings.publish(
        session,
        request,
        Published {
            authority,
            account_id,
            sign_out: view.account.can_sign_out,
            revision,
            efforts,
            reset_candidates,
            catalogs: IntegrationCatalogs::default(),
            integration_owner,
            home,
        },
    )?;
    Ok(view)
}

async fn catalog_efforts(browser: &CodexBrowser) -> BTreeSet<String> {
    let mut efforts = BTreeSet::new();
    let mut seen = HashSet::new();
    let mut cursor = None;
    for _ in 0..10 {
        let Ok(page) = browser.models(cursor.as_deref(), TIMEOUT).await else {
            break;
        };
        efforts.extend(
            page.data
                .into_iter()
                .filter(|model| !model.hidden)
                .flat_map(|model| model.supported_reasoning_efforts)
                .map(|effort| effort.reasoning_effort)
                .filter(|effort| !effort.is_empty() && effort.len() <= 80),
        );
        match page.next_cursor {
            Some(next) if seen.insert(next.clone()) => cursor = Some(next),
            _ => break,
        }
    }
    efforts
}

fn report(error: impl std::fmt::Display) -> IpcError {
    eprintln!("{error}");
    IpcError::ProjectUnavailable
}
