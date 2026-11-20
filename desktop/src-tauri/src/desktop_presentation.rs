use std::{
    collections::BTreeSet,
    io::{self, Write},
    path::{Path, PathBuf},
    sync::{
        Mutex, OnceLock,
        atomic::{AtomicU64, Ordering},
    },
    time::Duration,
};

use codex_gui_core::{
    appearance::{
        Appearance, AppearanceMode, AppearancePreferences, AppearanceSelection, AppearanceUpdate,
        AppearanceView, preset_choices,
    },
    ipc::{IpcError, WORKSPACE_WINDOW},
};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, Manager, State, Theme, WebviewWindow, Window, WindowEvent};
use tauri_plugin_clipboard_manager::ClipboardExt;
use uuid::Uuid;

use crate::{
    file_actions_ipc::{export_destination, fixture_data, persist_export},
    fixture::Verification,
    project_ipc::authorize_view,
};

pub(crate) mod window;

const CHANGED: &str = "desktop:appearance";

pub struct DesktopPresentation {
    path: Option<PathBuf>,
    state: Mutex<PresentationState>,
    font_families: OnceLock<Vec<String>>,
    geometry_generation: AtomicU64,
}

struct PresentationState {
    revision: Uuid,
    data: DesktopPreferences,
}

#[derive(Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", default)]
struct DesktopPreferences {
    appearance: AppearancePreferences,
    layout: Option<window::WindowLayout>,
    zoom_percent: u16,
}

impl Default for DesktopPreferences {
    fn default() -> Self {
        Self {
            appearance: AppearancePreferences::default(),
            layout: None,
            zoom_percent: 100,
        }
    }
}

impl DesktopPresentation {
    pub fn open(root: Option<&Path>) -> Self {
        let path = root.map(|root| root.join("presentation.json"));
        let data = path
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
        Self {
            path,
            state: Mutex::new(PresentationState {
                revision: Uuid::new_v4(),
                data,
            }),
            font_families: OnceLock::new(),
            geometry_generation: AtomicU64::new(0),
        }
    }

    fn persist(&self, preferences: &DesktopPreferences) -> Result<(), IpcError> {
        let Some(path) = &self.path else {
            return Ok(());
        };
        let parent = path.parent().ok_or(IpcError::ProjectUnavailable)?;
        let mut temporary = tempfile::NamedTempFile::new_in(parent).map_err(report)?;
        serde_json::to_writer_pretty(&mut temporary, preferences).map_err(report)?;
        temporary.write_all(b"\n").map_err(report)?;
        temporary.as_file().sync_all().map_err(report)?;
        temporary.persist(path).map_err(report)?;
        Ok(())
    }

    fn fonts(&self) -> &[String] {
        self.font_families.get_or_init(|| {
            let mut database = fontdb::Database::new();
            database.load_system_fonts();
            database
                .faces()
                .filter_map(|face| face.families.first())
                .map(|(name, _)| name)
                .filter(|name| {
                    !name.starts_with('.')
                        && !name.starts_with('@')
                        && !name.chars().any(char::is_control)
                })
                .cloned()
                .collect::<BTreeSet<_>>()
                .into_iter()
                .collect()
        })
    }

    pub fn initial_theme(&self) -> Option<Theme> {
        forced_theme(
            self.state
                .lock()
                .expect("appearance lock poisoned")
                .data
                .appearance
                .mode,
        )
    }

    fn view(&self, native_theme: Option<Theme>) -> AppearanceView {
        let state = self.state.lock().expect("appearance lock poisoned");
        let mode = state.data.appearance.mode;
        let appearance = effective_theme(mode, native_theme);
        let profile = state.data.appearance.profile(appearance).clone();
        let revision = state.revision;
        drop(state);
        AppearanceView {
            selection: AppearanceSelection {
                revision,
                appearance,
            },
            mode,
            resolved_fonts: profile.resolved_fonts(appearance, self.fonts()),
            resolved_accent: profile.resolved_accent(),
            profile,
            presets: preset_choices(appearance),
        }
    }

    fn capture_theme(
        &self,
        selection: &AppearanceSelection,
        native_theme: Option<Theme>,
    ) -> Result<String, IpcError> {
        let state = self.state.lock().expect("appearance lock poisoned");
        state.validate(selection, native_theme)?;
        state
            .data
            .appearance
            .profile(selection.appearance)
            .export_theme(selection.appearance)
            .map_err(report)
    }

    pub fn initialize_window(&self, window: &WebviewWindow) {
        let state = self.state.lock().expect("appearance lock poisoned");
        let layout = state.data.layout.clone();
        let zoom = state.data.zoom_percent.clamp(80, 160);
        drop(state);
        if let Some(layout) = layout {
            layout.restore(window);
        }
        if zoom != 100 {
            let _ = window.set_zoom(f64::from(zoom) / 100.0);
        }
    }

    fn refresh_layout(&self, window: &WebviewWindow) {
        if self.path.is_none() {
            return;
        }
        let Some(layout) = window::WindowLayout::capture(window) else {
            return;
        };
        let mut state = self.state.lock().expect("appearance lock poisoned");
        if state.data.layout.as_ref() == Some(&layout) {
            return;
        }
        let mut data = state.data.clone();
        data.layout = Some(layout);
        if self.persist(&data).is_ok() {
            state.data = data;
        }
    }
}

impl PresentationState {
    fn validate(
        &self,
        selection: &AppearanceSelection,
        native_theme: Option<Theme>,
    ) -> Result<(), IpcError> {
        if self.revision != selection.revision
            || effective_theme(self.data.appearance.mode, native_theme) != selection.appearance
        {
            return Err(IpcError::StaleSelection);
        }
        Ok(())
    }
}

pub fn on_window_event(window: &Window, event: &WindowEvent) {
    if window.label() != WORKSPACE_WINDOW {
        return;
    }
    let app = window.app_handle();
    let Some(state) = app.try_state::<DesktopPresentation>() else {
        return;
    };
    let Some(web) = app.get_webview_window(WORKSPACE_WINDOW) else {
        return;
    };
    match event {
        WindowEvent::ThemeChanged(theme) => {
            let theme = *theme;
            tauri::async_runtime::spawn_blocking(move || {
                let state = web.state::<DesktopPresentation>();
                let current = web.theme().ok().or(Some(theme));
                let _ = web.emit(CHANGED, state.view(current));
            });
        }
        WindowEvent::Moved(_)
        | WindowEvent::Resized(_)
        | WindowEvent::ScaleFactorChanged { .. } => {
            let generation = state.geometry_generation.fetch_add(1, Ordering::AcqRel) + 1;
            tauri::async_runtime::spawn(async move {
                tokio::time::sleep(Duration::from_millis(260)).await;
                let latest = web.state::<DesktopPresentation>();
                if generation == latest.geometry_generation.load(Ordering::Acquire) {
                    latest.refresh_layout(&web);
                }
            });
        }
        WindowEvent::CloseRequested { .. } => state.refresh_layout(&web),
        _ => {}
    }
}

#[tauri::command]
pub async fn read_desktop_appearance(
    window: WebviewWindow,
    state: State<'_, DesktopPresentation>,
) -> Result<AppearanceView, IpcError> {
    authorize_view(&window)?;
    Ok(state.view(window.theme().ok()))
}

#[tauri::command]
pub async fn desktop_font_families(
    window: WebviewWindow,
    state: State<'_, DesktopPresentation>,
) -> Result<Vec<String>, IpcError> {
    authorize_view(&window)?;
    Ok(state.fonts().to_vec())
}

#[tauri::command]
pub async fn update_desktop_appearance(
    window: WebviewWindow,
    state: State<'_, DesktopPresentation>,
    update: AppearanceUpdate,
) -> Result<AppearanceView, IpcError> {
    authorize_view(&window)?;
    let native_theme = window.theme().ok();
    let (old_mode, new_mode) = {
        let mut current = state.state.lock().expect("appearance lock poisoned");
        current.validate(&update.selection, native_theme)?;
        let mut data = current.data.clone();
        if !data
            .appearance
            .apply(update.selection.appearance, update.edit)
        {
            return Err(IpcError::StaleSelection);
        }
        let old_mode = current.data.appearance.mode;
        let new_mode = data.appearance.mode;
        state.persist(&data)?;
        current.data = data;
        current.revision = Uuid::new_v4();
        (old_mode, new_mode)
    };
    if old_mode != new_mode
        && let Err(error) = window.set_theme(forced_theme(new_mode))
    {
        eprintln!("{error}");
    }
    let view = state.view(window.theme().ok().or(native_theme));
    window.emit(CHANGED, &view).map_err(report)?;
    Ok(view)
}

#[tauri::command]
pub async fn copy_desktop_theme(
    window: WebviewWindow,
    state: State<'_, DesktopPresentation>,
    selection: AppearanceSelection,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    let theme = state.capture_theme(&selection, window.theme().ok())?;
    if *window.state::<Verification>() == Verification::Appearance {
        return persist_export(
            None,
            fixture_data(&window)?.join("Copied Theme.json"),
            theme.into_bytes(),
        )
        .await;
    }
    window.clipboard().write_text(theme).map_err(report)
}

#[tauri::command]
pub async fn export_desktop_theme(
    window: WebviewWindow,
    state: State<'_, DesktopPresentation>,
    selection: AppearanceSelection,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    let theme = state.capture_theme(&selection, window.theme().ok())?;
    let target = if *window.state::<Verification>() == Verification::Appearance {
        let directory = fixture_data(&window)?;
        std::fs::write(directory.join("fixture-theme-export-captured"), []).map_err(report)?;
        tokio::time::sleep(Duration::from_millis(500)).await;
        Some(directory.join("Theme.json"))
    } else {
        export_destination(&window, Path::new("Theme.json")).await?
    };
    if let Some(target) = target {
        persist_export(None, target, theme.into_bytes()).await?;
    }
    Ok(())
}

fn forced_theme(mode: AppearanceMode) -> Option<Theme> {
    match mode {
        AppearanceMode::System => None,
        AppearanceMode::Light => Some(Theme::Light),
        AppearanceMode::Dark => Some(Theme::Dark),
    }
}

fn effective_theme(mode: AppearanceMode, native_theme: Option<Theme>) -> Appearance {
    match forced_theme(mode).or(native_theme) {
        Some(Theme::Dark) => Appearance::Dark,
        _ => Appearance::Light,
    }
}

fn report(error: impl std::fmt::Display) -> IpcError {
    eprintln!("{error}");
    IpcError::ProjectUnavailable
}

#[tauri::command]
pub fn appearance_fixture_action(
    window: WebviewWindow,
    verification: State<'_, Verification>,
    action: String,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    if *verification != Verification::Appearance
        && !(*verification == Verification::AppearanceRestore && action == "settings")
    {
        return Err(IpcError::UnauthorizedWindow);
    }
    if action == "resize" {
        return window
            .set_size(tauri::LogicalSize::new(900.0, 640.0))
            .map_err(report);
    }
    if !matches!(
        action.as_str(),
        "settings" | "fullscreen" | "zoomIn" | "zoomOut" | "zoomReset"
    ) {
        return Err(IpcError::UnauthorizedWindow);
    }
    let menu = window
        .app_handle()
        .menu()
        .ok_or(IpcError::ProjectUnavailable)?;
    let has_action = menu.items().map_err(report)?.iter().any(|item| {
        item.as_submenu()
            .is_some_and(|section| section.get(&action).is_some())
    });
    if !has_action {
        return Err(IpcError::ProjectUnavailable);
    }
    window::dispatch_menu(&window, &action)
}

#[tauri::command]
pub fn appearance_fixture_state(
    window: WebviewWindow,
    verification: State<'_, Verification>,
    state: State<'_, DesktopPresentation>,
) -> Result<serde_json::Value, IpcError> {
    authorize_view(&window)?;
    if !matches!(
        *verification,
        Verification::Appearance | Verification::AppearanceRestore
    ) {
        return Err(IpcError::UnauthorizedWindow);
    }
    let scale = window.scale_factor().map_err(report)?;
    let size = window
        .inner_size()
        .map_err(report)?
        .to_logical::<u32>(scale);
    let zoom = state
        .state
        .lock()
        .expect("appearance lock poisoned")
        .data
        .zoom_percent;
    let captured = fixture_data(&window)?
        .join("fixture-theme-export-captured")
        .is_file();
    Ok(serde_json::json!({
        "width": size.width, "height": size.height, "fullscreen": window.is_fullscreen().map_err(report)?,
        "scale": scale, "zoom": zoom, "exportCaptured": captured,
    }))
}

#[tauri::command]
pub fn verify_appearance_result(
    window: WebviewWindow,
    verification: State<'_, Verification>,
    state: State<'_, DesktopPresentation>,
    failure: Option<String>,
    evidence: serde_json::Value,
) -> Result<(), IpcError> {
    authorize_view(&window)?;
    if !matches!(
        *verification,
        Verification::Appearance | Verification::AppearanceRestore
    ) {
        return Err(IpcError::UnauthorizedWindow);
    }
    if let Some(failure) = failure {
        eprintln!("Appearance verification failed: {failure}");
        window.app_handle().exit(1);
    } else {
        state.refresh_layout(&window);
        println!("Verified installed desktop appearance and layout: {evidence}");
        window.app_handle().exit(0);
    }
    Ok(())
}
