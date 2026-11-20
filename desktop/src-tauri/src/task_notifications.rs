use std::{
    collections::{HashSet, VecDeque},
    io::{self, Write},
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
};

use codex_gui_core::{
    codex::ServerEvent,
    files::FileRevision,
    identity::ConnectionIdentity,
    ipc::{IpcError, SidebarChatKey, WORKSPACE_WINDOW},
    notifications::{
        CustomAlertSound, NotificationEdit, NotificationPreferences, NotificationUpdate,
        NotificationView, TaskAlertCategory, TaskAlertSound, sound::AlertAudio,
    },
    storage::attachments::AttachmentStore,
    workspace::{InteractionKind, RoutedEvent},
};
use serde::Serialize;
use tauri::{AppHandle, Manager, State, WebviewWindow};
use tauri_plugin_dialog::DialogExt;
use tokio::sync::{Semaphore, oneshot};
use uuid::Uuid;

use crate::{
    fixture::Verification,
    project_ipc::{ProjectIpc, authorize_view},
};

mod platform;

const MAX_EVENT_HISTORY: usize = 512;
const MAX_DELIVERED: usize = 64;

pub struct TaskNotifications {
    path: Option<PathBuf>,
    selected: Mutex<Preferences>,
    delivery: Delivery,
    recent: Mutex<(HashSet<AlertKey>, VecDeque<AlertKey>)>,
    slots: Arc<Semaphore>,
}

struct Preferences {
    revision: Uuid,
    value: NotificationPreferences,
}

enum Delivery {
    Native,
    Fixture(Mutex<FixtureDelivery>),
    Off,
}

#[derive(Default)]
struct FixtureDelivery {
    allowed: bool,
    focused: bool,
    denied: usize,
    delivered: Vec<Alert>,
    next_sound: Option<PathBuf>,
}

#[derive(Clone, Eq, PartialEq, Hash)]
struct AlertKey {
    project: String,
    chat: String,
    turn: String,
    item: String,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct Alert {
    key: SidebarChatKey,
    category: TaskAlertCategory,
    title: &'static str,
    body: String,
}

impl TaskNotifications {
    pub fn open(root: Option<&Path>, mode: Verification) -> Self {
        let path = root.map(|root| root.join("notifications.json"));
        let value = path
            .as_ref()
            .and_then(|path| match std::fs::read(path) {
                Ok(data) => serde_json::from_slice(&data)
                    .inspect_err(|error| eprintln!("{error}"))
                    .ok(),
                Err(error) if error.kind() == io::ErrorKind::NotFound => None,
                Err(error) => {
                    eprintln!("{error}");
                    None
                }
            })
            .unwrap_or_default();
        let delivery = match mode {
            Verification::None => Delivery::Native,
            Verification::Notifications => Delivery::Fixture(Mutex::default()),
            _ => Delivery::Off,
        };
        Self {
            path,
            selected: Mutex::new(Preferences {
                revision: Uuid::new_v4(),
                value,
            }),
            delivery,
            recent: Mutex::default(),
            slots: Arc::new(Semaphore::new(MAX_DELIVERED)),
        }
    }

    fn replace(
        &self,
        current: &mut Preferences,
        value: NotificationPreferences,
    ) -> Result<(), IpcError> {
        let target = self.path.as_ref().ok_or(IpcError::ProjectUnavailable)?;
        let parent = target.parent().ok_or(IpcError::ProjectUnavailable)?;
        let mut temporary = tempfile::NamedTempFile::new_in(parent).map_err(report)?;
        serde_json::to_writer_pretty(&mut temporary, &value).map_err(report)?;
        temporary.write_all(b"\n").map_err(report)?;
        temporary.as_file().sync_all().map_err(report)?;
        temporary.persist(target).map_err(report)?;
        current.revision = Uuid::new_v4();
        current.value = value;
        Ok(())
    }

    fn view(&self, may_request_permission: bool) -> NotificationView {
        let selected = self
            .selected
            .lock()
            .expect("notification preferences lock poisoned");
        let value = &selected.value;
        NotificationView {
            revision: selected.revision,
            completions: value.completions,
            permissions: value.permissions,
            questions: value.questions,
            sound: value.sound,
            custom_name: value.custom.as_ref().map(|sound| sound.name.clone()),
            may_request_permission,
        }
    }

    fn sound_root(&self) -> Option<PathBuf> {
        Some(self.path.as_ref()?.parent()?.join("notification-sounds"))
    }

    fn custom_path(&self, sound: &CustomAlertSound) -> Option<PathBuf> {
        if sound.digest.len() != 64 || !sound.digest.bytes().all(|byte| byte.is_ascii_hexdigit()) {
            return None;
        }
        Some(self.sound_root()?.join(format!("{}.wav", sound.digest)))
    }

    fn remember(&self, key: AlertKey) -> bool {
        let mut recent = self
            .recent
            .lock()
            .expect("notification history lock poisoned");
        let (keys, order) = &mut *recent;
        if !keys.insert(key.clone()) {
            return false;
        }
        order.push_back(key);
        if order.len() > MAX_EVENT_HISTORY
            && let Some(first) = order.pop_front()
        {
            keys.remove(&first);
        }
        true
    }

    fn focused(&self, app: &AppHandle) -> bool {
        if let Delivery::Fixture(fixture) = &self.delivery {
            return fixture
                .lock()
                .expect("notification fixture lock poisoned")
                .focused;
        }
        app.get_webview_window(WORKSPACE_WINDOW)
            .is_some_and(|window| window.is_focused().unwrap_or(false))
    }

    async fn access(&self, app: &AppHandle, prompt: bool) -> platform::Access {
        match &self.delivery {
            Delivery::Native => platform::access(&app.config().identifier, prompt).await,
            Delivery::Fixture(fixture) => platform::Access {
                allowed: fixture
                    .lock()
                    .expect("notification fixture lock poisoned")
                    .allowed,
                may_request: false,
                sound: false,
            },
            Delivery::Off => platform::Access::default(),
        }
    }
}

pub(crate) fn observe(
    app: &AppHandle,
    store: &AttachmentStore,
    connection: &ConnectionIdentity,
    routed: &RoutedEvent,
    terminal_was_running: impl FnOnce(&str, &str) -> bool,
) {
    let state = app.state::<TaskNotifications>();
    if matches!(state.delivery, Delivery::Off) {
        return;
    }
    let Some(project) = connection
        .workspace
        .checkout
        .as_ref()
        .map(|checkout| checkout.storage_key())
    else {
        return;
    };
    let Some((thread, turn, item, category, title)) = transition(routed, terminal_was_running)
    else {
        return;
    };
    if !state.remember(AlertKey {
        project: project.clone(),
        chat: thread.to_owned(),
        turn: turn.to_owned(),
        item,
    }) {
        return;
    }
    let focused = state.focused(app);
    if !state
        .selected
        .lock()
        .expect("notification preferences lock poisoned")
        .value
        .allows(category, focused)
    {
        return;
    }
    let key = SidebarChatKey {
        project_id: project,
        chat_id: thread.to_owned(),
    };
    let body = store
        .sidebar_view(None)
        .ok()
        .and_then(|view| {
            view.chats
                .into_iter()
                .find(|chat| chat.key == key)
                .map(|chat| chat.title)
        })
        .unwrap_or_else(|| "Codex task".into());
    let alert = Alert {
        key,
        category,
        title,
        body,
    };
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        deliver(app, alert).await;
    });
}

fn transition(
    event: &RoutedEvent,
    terminal_was_running: impl FnOnce(&str, &str) -> bool,
) -> Option<(&str, &str, String, TaskAlertCategory, &'static str)> {
    match event {
        RoutedEvent::Interaction(request) => {
            let (category, title) = if request.kind == InteractionKind::Question {
                (TaskAlertCategory::Question, "Answer needed")
            } else {
                (TaskAlertCategory::Permission, "Approval needed")
            };
            let identity = &request.identity;
            Some((
                &identity.thread.0,
                &identity.turn.0,
                format!("{category:?}:{}", identity.item),
                category,
                title,
            ))
        }
        RoutedEvent::Conversation {
            thread,
            event: ServerEvent::Notification { method, params },
        } if method == "turn/completed" => {
            let turn = params["turn"]["id"].as_str()?;
            if !terminal_was_running(&thread.0, turn) {
                return None;
            }
            let title = match params["turn"]["status"].as_str()? {
                "completed" => "Task completed",
                "failed" => "Task failed",
                _ => return None,
            };
            Some((
                &thread.0,
                turn,
                "terminal".into(),
                TaskAlertCategory::Completion,
                title,
            ))
        }
        _ => None,
    }
}

async fn deliver(app: AppHandle, alert: Alert) {
    let state = app.state::<TaskNotifications>();
    let Ok(slot) = state.slots.clone().try_acquire_owned() else {
        return;
    };
    let access = state.access(&app, true).await;
    if !access.allowed {
        if let Delivery::Fixture(fixture) = &state.delivery {
            fixture
                .lock()
                .expect("notification fixture lock poisoned")
                .denied += 1;
        }
        return;
    }
    let preferences = state
        .selected
        .lock()
        .expect("notification preferences lock poisoned")
        .value
        .clone();
    if !preferences.allows(alert.category, state.focused(&app)) {
        return;
    }
    if let Delivery::Fixture(fixture) = &state.delivery {
        fixture
            .lock()
            .expect("notification fixture lock poisoned")
            .delivered
            .push(alert);
        return;
    }
    let custom = preferences
        .custom
        .as_ref()
        .and_then(|sound| state.custom_path(sound));
    let app_id = app.config().identifier.clone();
    let sound = if access.sound {
        preferences.sound
    } else {
        TaskAlertSound::None
    };
    tauri::async_runtime::spawn_blocking(move || {
        let _slot = slot;
        if let Err(error) = platform::post(&app_id, &alert, sound, custom, move |key| {
            activate(app, key)
        }) {
            eprintln!("{error}");
        }
    });
}

fn activate(app: AppHandle, key: SidebarChatKey) {
    tauri::async_runtime::spawn(async move {
        let Some(navigation) = app.state::<ProjectIpc>().navigation.get().cloned() else {
            return;
        };
        if navigation.open_notification_chat(key).await.is_ok()
            && let Some(window) = app.get_webview_window(WORKSPACE_WINDOW)
        {
            let _ = window.show();
            let _ = window.unminimize();
            let _ = window.set_focus();
        }
    });
}

#[tauri::command]
pub async fn read_notification_preferences(
    window: WebviewWindow,
    state: State<'_, TaskNotifications>,
) -> Result<NotificationView, IpcError> {
    authorize_view(&window)?;
    Ok(state.view(state.access(window.app_handle(), false).await.may_request))
}

#[tauri::command]
pub async fn update_notification_preferences(
    window: WebviewWindow,
    state: State<'_, TaskNotifications>,
    update: NotificationUpdate,
) -> Result<NotificationView, IpcError> {
    authorize_view(&window)?;
    {
        let mut current = state
            .selected
            .lock()
            .expect("notification preferences lock poisoned");
        if current.revision != update.revision {
            return Err(IpcError::StaleSelection);
        }
        let choosing_custom = matches!(
            &update.edit,
            NotificationEdit::SetSound {
                sound: TaskAlertSound::Custom
            }
        );
        let mut preferences = current.value.clone();
        if !preferences.apply(update.edit)
            || choosing_custom
                && preferences
                    .custom
                    .as_ref()
                    .and_then(|sound| state.custom_path(sound))
                    .is_none_or(|path| !path.is_file())
        {
            return Err(IpcError::StaleSelection);
        }
        state.replace(&mut current, preferences)?;
    }
    read_notification_preferences(window, state).await
}

#[tauri::command]
pub async fn request_notification_permission(
    window: WebviewWindow,
    state: State<'_, TaskNotifications>,
    revision: Uuid,
) -> Result<NotificationView, IpcError> {
    authorize_view(&window)?;
    if state
        .selected
        .lock()
        .expect("notification preferences lock poisoned")
        .revision
        != revision
    {
        return Err(IpcError::StaleSelection);
    }
    let access = state.access(window.app_handle(), true).await;
    Ok(state.view(access.may_request))
}

#[tauri::command]
pub async fn import_notification_sound(
    window: WebviewWindow,
    state: State<'_, TaskNotifications>,
    revision: Uuid,
) -> Result<NotificationView, IpcError> {
    authorize_view(&window)?;
    if state
        .selected
        .lock()
        .expect("notification preferences lock poisoned")
        .revision
        != revision
    {
        return Err(IpcError::StaleSelection);
    }
    let path = match &state.delivery {
        Delivery::Fixture(fixture) => fixture
            .lock()
            .expect("notification fixture lock poisoned")
            .next_sound
            .take(),
        _ => choose_sound(&window).await?,
    };
    if let Some(path) = path {
        let imported = tauri::async_runtime::spawn_blocking(move || prepare_sound(&path))
            .await
            .map_err(report)?;
        match imported {
            Ok((sound, bytes)) => {
                authorize_view(&window)?;
                let mut current = state
                    .selected
                    .lock()
                    .expect("notification preferences lock poisoned");
                if current.revision != revision {
                    return Err(IpcError::StaleSelection);
                }
                let destination = state
                    .custom_path(&sound)
                    .ok_or(IpcError::ProjectUnavailable)?;
                let created = persist_sound(&destination, &bytes)?;
                let mut value = current.value.clone();
                value.custom = Some(sound);
                value.sound = TaskAlertSound::Custom;
                if let Err(error) = state.replace(&mut current, value) {
                    if created {
                        let _ = std::fs::remove_file(destination);
                    }
                    return Err(error);
                }
            }
            Err(error) => eprintln!("{error}"),
        }
    }
    read_notification_preferences(window, state).await
}

async fn choose_sound(window: &WebviewWindow) -> Result<Option<PathBuf>, IpcError> {
    let (send, receive) = oneshot::channel();
    window
        .dialog()
        .file()
        .add_filter("Notification Sounds", &["wav", "aif", "aiff", "caf"])
        .pick_file(move |file| {
            let _ = send.send(file);
        });
    receive
        .await
        .map_err(report)?
        .map(|file| file.into_path().map_err(report))
        .transpose()
}

fn prepare_sound(
    path: &Path,
) -> Result<(CustomAlertSound, Vec<u8>), codex_gui_core::notifications::sound::AlertAudioError> {
    let audio = AlertAudio::read(path)?;
    let bytes = audio.wave_bytes();
    let digest = FileRevision::from_bytes(&bytes).digest;
    let name = path
        .file_stem()
        .and_then(|name| name.to_str())
        .unwrap_or("Custom")
        .to_owned();
    Ok((CustomAlertSound { digest, name }, bytes))
}

fn persist_sound(path: &Path, bytes: &[u8]) -> Result<bool, IpcError> {
    let root = path.parent().ok_or(IpcError::ProjectUnavailable)?;
    std::fs::create_dir_all(root).map_err(report)?;
    if path.try_exists().map_err(report)? {
        let metadata = path.metadata().map_err(report)?;
        if metadata.is_file()
            && metadata.len() == bytes.len() as u64
            && std::fs::read(path).map_err(report)? == bytes
        {
            return Ok(false);
        }
        return Err(IpcError::StaleSelection);
    }
    let mut staged = tempfile::NamedTempFile::new_in(root).map_err(report)?;
    staged.write_all(bytes).map_err(report)?;
    staged.as_file().sync_all().map_err(report)?;
    staged.persist_noclobber(path).map_err(report)?;
    Ok(true)
}

fn report(error: impl std::fmt::Display) -> IpcError {
    eprintln!("{error}");
    IpcError::ProjectUnavailable
}

fn fixture_delivery(state: &TaskNotifications) -> Result<&Mutex<FixtureDelivery>, IpcError> {
    match &state.delivery {
        Delivery::Fixture(fixture) => Ok(fixture),
        _ => Err(IpcError::UnauthorizedWindow),
    }
}

#[tauri::command]
pub fn configure_notification_fixture(
    window: WebviewWindow,
    state: State<'_, TaskNotifications>,
    allowed: bool,
    focused: bool,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    let mut fixture = fixture_delivery(&state)?
        .lock()
        .expect("notification fixture lock poisoned");
    fixture.allowed = allowed;
    fixture.focused = focused;
    Ok(())
}

#[tauri::command]
pub fn choose_notification_fixture_sound(
    window: WebviewWindow,
    state: State<'_, TaskNotifications>,
    choice: String,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    let fixture = fixture_delivery(&state)?;
    let file = match choice.as_str() {
        "wav" => Some("Fixture WAV.wav"),
        "aiff" => Some("Fixture AIFF.aiff"),
        "caf" => Some("Fixture CAF.caf"),
        "invalid" => Some("Invalid.wav"),
        "long" => Some("Long.wav"),
        "cancel" => None,
        _ => return Err(IpcError::UnauthorizedWindow),
    };
    let root = crate::file_actions_ipc::fixture_data(&window)?;
    fixture
        .lock()
        .expect("notification fixture lock poisoned")
        .next_sound = file.map(|name| root.join(name));
    Ok(())
}

#[tauri::command]
pub fn notification_fixture_outcomes(
    window: WebviewWindow,
    state: State<'_, TaskNotifications>,
) -> Result<serde_json::Value, IpcError> {
    authorize_view(&window)?;
    let fixture = fixture_delivery(&state)?
        .lock()
        .expect("notification fixture lock poisoned");
    Ok(serde_json::json!({"delivered": fixture.delivered, "denied": fixture.denied}))
}

#[tauri::command]
pub fn activate_notification_fixture(
    window: WebviewWindow,
    state: State<'_, TaskNotifications>,
    index: usize,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    let key = fixture_delivery(&state)?
        .lock()
        .expect("notification fixture lock poisoned")
        .delivered
        .get(index)
        .ok_or(IpcError::StaleSelection)?
        .key
        .clone();
    activate(window.app_handle().clone(), key);
    Ok(())
}

#[tauri::command]
pub fn verify_notifications_result(
    window: WebviewWindow,
    state: State<'_, TaskNotifications>,
    failure: Option<String>,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    let fixture = fixture_delivery(&state)?
        .lock()
        .expect("notification fixture lock poisoned");
    if let Some(failure) = failure {
        eprintln!("Notification verification failed: {failure}");
        window.app_handle().exit(1);
    } else {
        println!(
            "Verified installed desktop notifications: {}",
            serde_json::json!({"delivered": fixture.delivered, "denied": fixture.denied})
        );
        window.app_handle().exit(0);
    }
    Ok(())
}
