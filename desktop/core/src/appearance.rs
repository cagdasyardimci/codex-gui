use std::sync::OnceLock;

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use ts_rs::TS;
use uuid::Uuid;

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "lowercase")]
pub enum AppearanceMode {
    #[default]
    System,
    Light,
    Dark,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "lowercase")]
pub enum Appearance {
    Light,
    Dark,
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "lowercase")]
pub enum AppearanceAccent {
    #[default]
    Default,
    Blue,
    Green,
    Yellow,
    Pink,
    Orange,
    Purple,
    Black,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum ColorRole {
    Background,
    Foreground,
    Accent,
    DiffAdded,
    DiffRemoved,
    Skill,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "lowercase")]
pub enum TypefaceRole {
    Ui,
    Content,
    Code,
}

#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase", default)]
pub struct AppearanceFonts {
    pub ui: Option<String>,
    pub content: Option<String>,
    pub code: Option<String>,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize, TS)]
pub struct AppearanceSizes {
    pub ui: u8,
    pub content: u8,
    pub code: u8,
}

impl Default for AppearanceSizes {
    fn default() -> Self {
        Self {
            ui: 14,
            content: 15,
            code: 12,
        }
    }
}

impl AppearanceSizes {
    fn set(&mut self, role: TypefaceRole, size: u8) {
        match role {
            TypefaceRole::Ui => self.ui = size.clamp(11, 16),
            TypefaceRole::Content => self.content = size.clamp(12, 24),
            TypefaceRole::Code => self.code = size.clamp(8, 24),
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct AppearanceColors {
    pub background: u32,
    pub foreground: u32,
    pub accent: u32,
    pub diff_added: u32,
    pub diff_removed: u32,
    pub skill: u32,
}

impl AppearanceColors {
    fn set(&mut self, role: ColorRole, value: u32) {
        let channel = match role {
            ColorRole::Background => &mut self.background,
            ColorRole::Foreground => &mut self.foreground,
            ColorRole::Accent => &mut self.accent,
            ColorRole::DiffAdded => &mut self.diff_added,
            ColorRole::DiffRemoved => &mut self.diff_removed,
            ColorRole::Skill => &mut self.skill,
        };
        *channel = value & 0xff_ff_ff;
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct AppearanceProfile {
    pub colors: AppearanceColors,
    pub named_accent: Option<AppearanceAccent>,
    pub contrast: u8,
    pub colorize_messages: bool,
    pub translucent_sidebar: bool,
    pub preset_id: Option<String>,
    pub code_theme: Option<String>,
    pub fonts: AppearanceFonts,
    pub sizes: AppearanceSizes,
}

impl AppearanceProfile {
    pub fn native(appearance: Appearance) -> Self {
        let (background, foreground, accent, skill, contrast) = match appearance {
            Appearance::Light => (0xff_ff_ff, 0x0d_0d_0d, 0x01_69_cc, 0x75_1e_d9, 45),
            Appearance::Dark => (0x11_11_11, 0xfc_fc_fc, 0x3a_83_f7, 0xb0_6d_ff, 60),
        };
        Self {
            colors: AppearanceColors {
                background,
                foreground,
                accent,
                diff_added: 0x00_a2_40,
                diff_removed: 0xe0_2e_2a,
                skill,
            },
            named_accent: None,
            contrast,
            colorize_messages: true,
            translucent_sidebar: true,
            preset_id: None,
            code_theme: None,
            fonts: AppearanceFonts::default(),
            sizes: AppearanceSizes::default(),
        }
    }

    pub fn resolved_fonts(&self, appearance: Appearance, installed: &[String]) -> AppearanceFonts {
        let preset = self.preset(appearance);
        let fallback_ui = preset.and_then(|preset| preset.ui_font_family.as_deref());
        let fallback_content = preset
            .and_then(|preset| preset.content_font_family.as_deref())
            .or(fallback_ui);
        let fallback_code = preset.and_then(|preset| preset.code_font_family.as_deref());
        let resolve = |requested: Option<&str>, theme: Option<&str>| {
            let find = |family: &str| {
                installed
                    .iter()
                    .find(|name| name.eq_ignore_ascii_case(family))
            };
            let family = if let Some(requested) = requested {
                find(requested)
            } else {
                theme.and_then(|list| {
                    list.split(',')
                        .find_map(|requested| find(requested.trim().trim_matches('"')))
                })
            };
            family.cloned()
        };
        AppearanceFonts {
            ui: resolve(self.fonts.ui.as_deref(), fallback_ui),
            content: resolve(
                self.fonts.content.as_deref().or(self.fonts.ui.as_deref()),
                fallback_content,
            ),
            code: resolve(self.fonts.code.as_deref(), fallback_code),
        }
    }

    pub fn resolved_accent(&self) -> u32 {
        match self.named_accent {
            None => self.colors.accent,
            Some(AppearanceAccent::Default | AppearanceAccent::Blue | AppearanceAccent::Black) => {
                0x3a_83_f7
            }
            Some(AppearanceAccent::Green) => 0x53_b5_59,
            Some(AppearanceAccent::Yellow) => 0xf6_c5_43,
            Some(AppearanceAccent::Pink) => 0xf0_77_af,
            Some(AppearanceAccent::Orange) => 0xee_7c_37,
            Some(AppearanceAccent::Purple) => 0xa6_7d_f2,
        }
    }

    fn preset(&self, appearance: Appearance) -> Option<&'static AppearancePreset> {
        let id = self.preset_id.as_deref()?;
        appearance_presets()
            .iter()
            .find(|preset| preset.id == id && preset.appearance == appearance)
    }

    pub fn export_theme(&self, appearance: Appearance) -> Result<String, serde_json::Error> {
        let preset = self.preset(appearance);
        let has_custom_fonts = self.fonts != AppearanceFonts::default()
            || preset.is_some_and(|preset| {
                preset.ui_font_family.is_some()
                    || preset.content_font_family.is_some()
                    || preset.code_font_family.is_some()
            });
        let mut value = json!({
            "background": self.colors.background, "foreground": self.colors.foreground,
            "accent": self.colors.accent, "contrast": self.contrast, "diffAdded": self.colors.diff_added,
            "diffRemoved": self.colors.diff_removed, "skill": self.colors.skill,
            "opaqueWindows": !self.translucent_sidebar, "colorizeMessages": self.colorize_messages,
            "hasCustomFonts": has_custom_fonts,
        });
        for (key, optional) in [
            ("namedAccent", json!(self.named_accent)),
            ("presetID", json!(self.preset_id)),
            ("codeThemeID", json!(self.code_theme)),
            ("uiFontFamily", json!(self.fonts.ui)),
            ("contentFontFamily", json!(self.fonts.content)),
            ("codeFontFamily", json!(self.fonts.code)),
        ] {
            if optional != Value::Null {
                value[key] = optional;
            }
        }
        serde_json::to_string_pretty(&value)
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", default)]
pub struct AppearancePreferences {
    pub mode: AppearanceMode,
    pub light: AppearanceProfile,
    pub dark: AppearanceProfile,
}

impl Default for AppearancePreferences {
    fn default() -> Self {
        Self {
            mode: AppearanceMode::System,
            light: AppearanceProfile::native(Appearance::Light),
            dark: AppearanceProfile::native(Appearance::Dark),
        }
    }
}

impl AppearancePreferences {
    pub fn profile(&self, appearance: Appearance) -> &AppearanceProfile {
        match appearance {
            Appearance::Light => &self.light,
            Appearance::Dark => &self.dark,
        }
    }

    pub fn apply(&mut self, appearance: Appearance, edit: AppearanceEdit) -> bool {
        let profile = match appearance {
            Appearance::Light => &mut self.light,
            Appearance::Dark => &mut self.dark,
        };
        match edit {
            AppearanceEdit::SetMode { mode } => self.mode = mode,
            AppearanceEdit::SetPreset { preset } => {
                let sizes = profile.sizes;
                let colorize_messages = profile.colorize_messages;
                if let Some(id) = preset {
                    let Some(next) = appearance_presets()
                        .iter()
                        .find(|entry| entry.id == id && entry.appearance == appearance)
                    else {
                        return false;
                    };
                    *profile = next.profile(sizes);
                } else {
                    *profile = AppearanceProfile::native(appearance);
                    profile.sizes = sizes;
                }
                profile.colorize_messages = colorize_messages;
            }
            AppearanceEdit::SetColor { role, color } => {
                if role == ColorRole::Accent {
                    profile.named_accent = None;
                }
                profile.colors.set(role, color);
            }
            AppearanceEdit::SetAccent { accent } => {
                profile.named_accent = Some(accent);
            }
            AppearanceEdit::SetContrast { value } => profile.contrast = value.min(100),
            AppearanceEdit::SetTranslucency { enabled } => profile.translucent_sidebar = enabled,
            AppearanceEdit::SetMessageColors { enabled } => profile.colorize_messages = enabled,
            AppearanceEdit::SetFont { role, family } => {
                if family.as_ref().is_some_and(|name| {
                    name.len() > 256 || name.trim().is_empty() || name.chars().any(char::is_control)
                }) {
                    return false;
                }
                match role {
                    TypefaceRole::Ui => profile.fonts.ui = family,
                    TypefaceRole::Content => profile.fonts.content = family,
                    TypefaceRole::Code => profile.fonts.code = family,
                }
            }
            AppearanceEdit::SetSize { role, size } => profile.sizes.set(role, size),
        }
        true
    }
}

#[derive(Clone, Debug, Deserialize, TS)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum AppearanceEdit {
    SetMode {
        mode: AppearanceMode,
    },
    SetPreset {
        preset: Option<String>,
    },
    SetColor {
        role: ColorRole,
        color: u32,
    },
    SetAccent {
        accent: AppearanceAccent,
    },
    SetContrast {
        value: u8,
    },
    SetTranslucency {
        enabled: bool,
    },
    SetMessageColors {
        enabled: bool,
    },
    SetFont {
        role: TypefaceRole,
        family: Option<String>,
    },
    SetSize {
        role: TypefaceRole,
        size: u8,
    },
}

#[derive(Clone, Debug, Deserialize, Serialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AppearanceSelection {
    pub revision: Uuid,
    pub appearance: Appearance,
}

#[derive(Clone, Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AppearanceUpdate {
    pub selection: AppearanceSelection,
    pub edit: AppearanceEdit,
}

#[derive(Clone, Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct AppearanceView {
    pub selection: AppearanceSelection,
    pub mode: AppearanceMode,
    pub profile: AppearanceProfile,
    pub resolved_fonts: AppearanceFonts,
    pub resolved_accent: u32,
    pub presets: Vec<AppearanceChoice>,
}

#[derive(Clone, Debug, Serialize, TS)]
pub struct AppearanceChoice {
    pub id: String,
    pub label: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct AppearancePreset {
    id: String,
    label: String,
    appearance: Appearance,
    code_theme: String,
    ui_font_family: Option<String>,
    code_font_family: Option<String>,
    content_font_family: Option<String>,
    #[serde(default)]
    opaque_windows: bool,
    #[serde(flatten)]
    colors: AppearanceColors,
    contrast: u8,
    named_accent: Option<AppearanceAccent>,
}

impl AppearancePreset {
    fn profile(&self, sizes: AppearanceSizes) -> AppearanceProfile {
        AppearanceProfile {
            colors: self.colors.clone(),
            named_accent: self.named_accent,
            contrast: self.contrast,
            colorize_messages: true,
            translucent_sidebar: !self.opaque_windows,
            preset_id: Some(self.id.clone()),
            code_theme: Some(self.code_theme.clone()),
            fonts: AppearanceFonts::default(),
            sizes,
        }
    }
}

fn appearance_presets() -> &'static [AppearancePreset] {
    static PRESETS: OnceLock<Vec<AppearancePreset>> = OnceLock::new();
    PRESETS.get_or_init(|| {
        serde_json::from_str(include_str!("appearance/presets.json"))
            .expect("valid appearance presets")
    })
}

pub fn preset_choices(appearance: Appearance) -> Vec<AppearanceChoice> {
    appearance_presets()
        .iter()
        .filter(|preset| preset.appearance == appearance)
        .map(|preset| AppearanceChoice {
            id: preset.id.clone(),
            label: preset.label.clone(),
        })
        .collect()
}
