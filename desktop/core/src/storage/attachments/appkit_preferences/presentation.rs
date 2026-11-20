use crate::{
    appearance::{
        AppearanceAccent, AppearanceFonts, AppearanceMode, AppearancePreferences,
        AppearanceProfile, AppearanceSizes,
    },
    notifications::{NotificationPreferences, TaskAlertSound, sound::AlertAudio},
};

use super::*;

#[derive(Default)]
pub struct AppKitDesktopPresentation {
    pub appearance: Option<AppearancePreferences>,
    pub layout: Option<AppKitPaneLayout>,
}

pub struct AppKitNotificationPreferences {
    pub settings: NotificationPreferences,
    pub sound: Option<(String, AlertAudio)>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AppKitPaneLayout {
    pub frame: [[f64; 2]; 2],
    pub navigation_width: Option<f64>,
    pub review_width: Option<f64>,
    pub navigation_collapsed: Option<bool>,
    pub review_collapsed: Option<bool>,
    pub review_visibility: Option<String>,
    pub pane_geometry_version: Option<u32>,
}

#[derive(Deserialize)]
struct ColorTheme {
    #[serde(default)]
    mode: AppearanceMode,
    light: Option<ColorProfile>,
    dark: Option<ColorProfile>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ColorProfile {
    background: u32,
    foreground: u32,
    accent: u32,
    contrast: i64,
    diff_added: Option<u32>,
    diff_removed: Option<u32>,
    skill: Option<u32>,
    named_accent: Option<AppearanceAccent>,
    colorize_messages: Option<bool>,
    #[serde(rename = "presetID")]
    preset_id: Option<String>,
    #[serde(rename = "codeThemeID")]
    code_theme: Option<String>,
    opaque_windows: Option<bool>,
    ui_font_family: Option<String>,
    content_font_family: Option<String>,
    code_font_family: Option<String>,
}

impl ColorProfile {
    fn apply(self, profile: &mut AppearanceProfile) {
        profile.colors.background = self.background & 0xff_ff_ff;
        profile.colors.foreground = self.foreground & 0xff_ff_ff;
        profile.colors.accent = self.accent & 0xff_ff_ff;
        profile.colors.diff_added = self.diff_added.unwrap_or(0x00_a2_40) & 0xff_ff_ff;
        profile.colors.diff_removed = self.diff_removed.unwrap_or(0xe0_2e_2a) & 0xff_ff_ff;
        profile.colors.skill = self.skill.unwrap_or(0xb0_6d_ff) & 0xff_ff_ff;
        profile.contrast = self.contrast.clamp(0, 100) as u8;
        profile.named_accent = self.named_accent;
        profile.colorize_messages = self.colorize_messages.unwrap_or(true);
        if let Some(opaque) = self.opaque_windows {
            profile.translucent_sidebar = !opaque;
        }
        profile.preset_id = self.preset_id;
        profile.code_theme = self.code_theme;
        profile.fonts = AppearanceFonts {
            ui: self.ui_font_family,
            content: self.content_font_family,
            code: self.code_font_family,
        };
    }
}

impl AppKitPreferences {
    pub fn presentation(&self) -> Result<AppKitDesktopPresentation, AppKitPreferenceError> {
        let color: Option<ColorTheme> = self.encoded("appearance.colorTheme")?;
        let typography = self.dictionary("appearance.typography");
        let appearance = if color.is_some() || typography.is_some() {
            let mut appearance = AppearancePreferences::default();
            if let Some(color) = color {
                appearance.mode = color.mode;
                if let Some(light) = color.light {
                    light.apply(&mut appearance.light);
                }
                if let Some(dark) = color.dark {
                    dark.apply(&mut appearance.dark);
                }
            }
            if let Some(typography) = typography {
                let sizes = AppearanceSizes {
                    ui: size(typography, "ui", 14, 11, 16),
                    content: size(typography, "content", 15, 12, 24),
                    code: size(typography, "code", 12, 8, 24),
                };
                appearance.light.sizes = sizes;
                appearance.dark.sizes = sizes;
            }
            Some(appearance)
        } else {
            None
        };
        let layout: Option<AppKitPaneLayout> = self.encoded("CodexGUI.windowLayout")?;
        let layout = layout.filter(|layout| {
            layout.frame.iter().flatten().all(|value| value.is_finite())
                && layout.frame[1].iter().all(|value| *value > 0.0)
        });
        Ok(AppKitDesktopPresentation { appearance, layout })
    }

    pub fn notification_preferences(
        &self,
    ) -> Result<Option<AppKitNotificationPreferences>, AppKitPreferenceError> {
        let value = |key| self.values.get(key);
        let completion = value("taskNotificationCompletionMode");
        let permissions = value("taskNotificationPermissionAlerts");
        let questions = value("taskNotificationQuestionAlerts");
        let chosen = value("taskNotificationSoundID");
        let enabled = value("taskNotificationSoundEnabled");
        if [completion, permissions, questions, chosen, enabled]
            .iter()
            .all(|v| v.is_none())
        {
            return Ok(None);
        }
        let mut settings = NotificationPreferences::default();
        if let Some(completions) = completion.and_then(|source| decode(source).ok()) {
            settings.completions = completions;
        }
        if let Some(permissions) = permissions.and_then(Plist::as_boolean) {
            settings.permissions = permissions;
        }
        if let Some(questions) = questions.and_then(Plist::as_boolean) {
            settings.questions = questions;
        }
        settings.sound = chosen
            .and_then(|source| decode(source).ok())
            .unwrap_or_else(|| {
                if enabled.and_then(Plist::as_boolean) == Some(false) {
                    TaskAlertSound::None
                } else {
                    TaskAlertSound::Default
                }
            });
        let audio = if let Some(name) = text(value("taskNotificationCustomSoundFilename")) {
            let extension = Path::new(name)
                .extension()
                .and_then(|ext| ext.to_str())
                .map(str::to_ascii_lowercase);
            if !name.starts_with("CodexGUI-")
                || name.contains('\\')
                || !matches!(extension.as_deref(), Some("wav" | "aiff" | "aif" | "caf"))
                || Path::new(name).components().count() != 1
                || Path::new(name).file_name().and_then(|name| name.to_str()) != Some(name)
            {
                return Err(AppKitPreferenceError::InvalidSource);
            }
            let source = self.root().join("notification-sounds").join(name);
            if !fs::symlink_metadata(&source)?.is_file() {
                return Err(AppKitPreferenceError::InvalidSource);
            }
            let display_name = source
                .file_stem()
                .and_then(|name| name.to_str())
                .unwrap_or(name)
                .to_owned();
            Some((
                display_name,
                AlertAudio::read(&source).map_err(io::Error::other)?,
            ))
        } else {
            if settings.sound == TaskAlertSound::Custom {
                return Err(AppKitPreferenceError::InvalidSource);
            }
            None
        };
        Ok(Some(AppKitNotificationPreferences {
            settings,
            sound: audio,
        }))
    }
}

fn size(typography: &Dictionary, role: &str, standard: u8, minimum: u8, maximum: u8) -> u8 {
    typography
        .get(role)
        .and_then(|value| {
            value
                .as_real()
                .or_else(|| value.as_signed_integer().map(|value| value as f64))
        })
        .filter(|size| size.is_finite())
        .map_or(standard, |size| {
            (size.round() as u8).clamp(minimum, maximum)
        })
}
