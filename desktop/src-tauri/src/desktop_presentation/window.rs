use tauri::{
    LogicalSize, PhysicalPosition,
    menu::{Menu, MenuBuilder, MenuItemBuilder, SubmenuBuilder},
};

use super::*;

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct WindowLayout {
    display: Option<String>,
    offset_x: f64,
    offset_y: f64,
    width: f64,
    height: f64,
}

impl WindowLayout {
    pub fn capture(window: &WebviewWindow) -> Option<Self> {
        if window.is_fullscreen().ok()?
            || window.is_maximized().unwrap_or(false)
            || window.is_minimized().unwrap_or(false)
        {
            return None;
        }
        let monitor = window.current_monitor().ok()??;
        let (scale, area) = (monitor.scale_factor(), monitor.work_area());
        let location = window.outer_position().ok()?;
        let size = window.inner_size().ok()?;
        Some(Self {
            display: monitor.name().cloned(),
            offset_x: (f64::from(location.x) - f64::from(area.position.x)) / scale,
            offset_y: (f64::from(location.y) - f64::from(area.position.y)) / scale,
            width: f64::from(size.width) / scale,
            height: f64::from(size.height) / scale,
        })
    }

    pub fn restore(&self, window: &WebviewWindow) {
        let Some(monitor) = window
            .available_monitors()
            .ok()
            .and_then(|monitors| {
                monitors
                    .into_iter()
                    .find(|monitor| monitor.name() == self.display.as_ref())
            })
            .or_else(|| window.primary_monitor().ok().flatten())
        else {
            return;
        };
        let (scale, area) = (monitor.scale_factor(), monitor.work_area());
        let width = (f64::from(area.size.width) / scale).max(1.0);
        let height = (f64::from(area.size.height) / scale).max(1.0);
        let client_width = self.width.clamp(520.0_f64.min(width), width);
        let client_height = self.height.clamp(400.0_f64.min(height), height);
        let decoration = window.outer_size().ok().zip(window.inner_size().ok());
        let (frame_width, frame_height) = decoration.map_or((0.0, 0.0), |(outer, inner)| {
            (
                f64::from(outer.width.saturating_sub(inner.width)) / scale,
                f64::from(outer.height.saturating_sub(inner.height)) / scale,
            )
        });
        let client_width = client_width.min((width - frame_width).max(1.0));
        let client_height = client_height.min((height - frame_height).max(1.0));
        let (target_x, target_y) = if monitor.name() == self.display.as_ref() {
            (self.offset_x, self.offset_y)
        } else {
            ((width - client_width) / 2.0, (height - client_height) / 2.0)
        };
        let x = target_x.clamp(0.0, (width - client_width - frame_width).max(0.0));
        let y = target_y.clamp(0.0, (height - client_height - frame_height).max(0.0));
        let _ = window.set_position(PhysicalPosition::new(
            area.position.x.saturating_add((x * scale).round() as i32),
            area.position.y.saturating_add((y * scale).round() as i32),
        ));
        let _ = window
            .set_size(LogicalSize::new(client_width, client_height).to_physical::<u32>(scale));
    }
}

pub fn menu(app: &AppHandle) -> tauri::Result<Menu<tauri::Wry>> {
    let settings = MenuItemBuilder::with_id("settings", "Settings…")
        .accelerator("CmdOrCtrl+Comma")
        .build(app)?;
    let application = SubmenuBuilder::new(app, "Codex GUI")
        .item(&settings)
        .separator()
        .quit()
        .build()?;
    let new_chat = MenuItemBuilder::with_id("newChat", "New Chat")
        .accelerator("CmdOrCtrl+N")
        .build(app)?;
    let close = MenuItemBuilder::with_id("closeWindow", "Close Window")
        .accelerator("CmdOrCtrl+W")
        .build(app)?;
    let file = SubmenuBuilder::new(app, "File")
        .items(&[&new_chat, &close])
        .build()?;
    let edit = SubmenuBuilder::new(app, "Edit");
    #[cfg(target_os = "macos")]
    let edit = edit.undo().redo().separator();
    #[cfg(not(target_os = "macos"))]
    let edit = edit.text("undo", "Undo").text("redo", "Redo").separator();
    let edit = edit.cut().copy().paste().select_all().build()?;
    let zoom_in = MenuItemBuilder::with_id("zoomIn", "Zoom In")
        .accelerator("CmdOrCtrl+Equal")
        .build(app)?;
    let zoom_out = MenuItemBuilder::with_id("zoomOut", "Zoom Out")
        .accelerator("CmdOrCtrl+Minus")
        .build(app)?;
    let zoom_reset = MenuItemBuilder::with_id("zoomReset", "Actual Size")
        .accelerator("CmdOrCtrl+Digit0")
        .build(app)?;
    let fullscreen = MenuItemBuilder::with_id("fullscreen", "Toggle Full Screen")
        .accelerator(if cfg!(target_os = "macos") {
            "Ctrl+Cmd+F"
        } else {
            "F11"
        })
        .build(app)?;
    let view = SubmenuBuilder::new(app, "View")
        .text("messageSearch", "Search Messages")
        .separator()
        .items(&[&zoom_in, &zoom_out, &zoom_reset])
        .separator()
        .item(&fullscreen)
        .build()?;
    MenuBuilder::new(app)
        .items(&[&application, &file, &edit, &view])
        .build()
}

pub fn dispatch_menu(window: &WebviewWindow, action: &str) -> Result<(), IpcError> {
    match action {
        "settings" | "newChat" | "messageSearch" | "undo" | "redo" => {
            window.emit("desktop:menu", action).map_err(report)
        }
        "closeWindow" => window.close().map_err(report),
        "fullscreen" => window
            .state::<DesktopPresentation>()
            .toggle_fullscreen(window),
        "zoomIn" | "zoomOut" | "zoomReset" => {
            let presentation = window.state::<DesktopPresentation>();
            let mut state = presentation.state.lock().expect("appearance lock poisoned");
            let mut data = state.data.clone();
            data.zoom_percent = match action {
                "zoomIn" => data.zoom_percent.saturating_add(10).min(160),
                "zoomOut" => data.zoom_percent.saturating_sub(10).max(80),
                _ => 100,
            };
            if data.zoom_percent == state.data.zoom_percent {
                return Ok(());
            }
            let previous = state.data.zoom_percent;
            window
                .set_zoom(f64::from(data.zoom_percent) / 100.0)
                .map_err(report)?;
            if let Err(error) = presentation.persist(&data) {
                let _ = window.set_zoom(f64::from(previous) / 100.0);
                return Err(error);
            }
            state.data = data;
            Ok(())
        }
        _ => Ok(()),
    }
}
