use serde::{Deserialize, Serialize};
use ts_rs::TS;
use uuid::Uuid;

pub mod sound;

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum TaskAlertCategory {
    Completion,
    Permission,
    Question,
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum TaskCompletionAlerts {
    #[default]
    Always,
    WhenUnfocused,
    Never,
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum TaskAlertSound {
    #[default]
    Default,
    Classic,
    None,
    Basso,
    Glass,
    Ping,
    Pop,
    Purr,
    Tink,
    Custom,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CustomAlertSound {
    pub digest: String,
    pub name: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", default)]
pub struct NotificationPreferences {
    pub completions: TaskCompletionAlerts,
    pub permissions: bool,
    pub questions: bool,
    pub sound: TaskAlertSound,
    pub custom: Option<CustomAlertSound>,
}

impl Default for NotificationPreferences {
    fn default() -> Self {
        Self {
            completions: TaskCompletionAlerts::default(),
            permissions: true,
            questions: true,
            sound: TaskAlertSound::default(),
            custom: None,
        }
    }
}

impl NotificationPreferences {
    pub fn allows(&self, category: TaskAlertCategory, focused: bool) -> bool {
        match category {
            TaskAlertCategory::Completion => match self.completions {
                TaskCompletionAlerts::Always => true,
                TaskCompletionAlerts::WhenUnfocused => !focused,
                TaskCompletionAlerts::Never => false,
            },
            TaskAlertCategory::Permission => self.permissions,
            TaskAlertCategory::Question => self.questions,
        }
    }

    pub fn apply(&mut self, edit: NotificationEdit) -> bool {
        match edit {
            NotificationEdit::SetCompletions { value } => self.completions = value,
            NotificationEdit::SetPermissions { enabled } => self.permissions = enabled,
            NotificationEdit::SetQuestions { enabled } => self.questions = enabled,
            NotificationEdit::SetSound { sound } => {
                if sound == TaskAlertSound::Custom && self.custom.is_none() {
                    return false;
                }
                self.sound = sound;
            }
        }
        true
    }
}

#[derive(Clone, Debug, Deserialize, TS)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum NotificationEdit {
    SetCompletions { value: TaskCompletionAlerts },
    SetPermissions { enabled: bool },
    SetQuestions { enabled: bool },
    SetSound { sound: TaskAlertSound },
}

#[derive(Clone, Debug, Deserialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct NotificationUpdate {
    pub revision: Uuid,
    pub edit: NotificationEdit,
}

#[derive(Clone, Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct NotificationView {
    pub revision: Uuid,
    pub completions: TaskCompletionAlerts,
    pub permissions: bool,
    pub questions: bool,
    pub sound: TaskAlertSound,
    pub custom_name: Option<String>,
    pub may_request_permission: bool,
}
