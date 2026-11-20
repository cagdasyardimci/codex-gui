use std::{error::Error, path::PathBuf};

use super::{Alert, SidebarChatKey, TaskAlertSound};

#[derive(Default)]
pub(super) struct Access {
    pub allowed: bool,
    pub may_request: bool,
    pub sound: bool,
}

#[cfg(target_os = "macos")]
pub(super) async fn access(_identifier: &str, prompt: bool) -> Access {
    use mac_usernotifications::{AuthorizationStatus, NotificationSettingStatus};
    let Ok(mut settings) = notify_rust::get_notification_settings().await else {
        return Access::default();
    };
    if prompt && settings.authorization_status == AuthorizationStatus::NotDetermined {
        if !notify_rust::request_auth().await.unwrap_or(false) {
            return Access::default();
        }
        let Ok(granted) = notify_rust::get_notification_settings().await else {
            return Access::default();
        };
        settings = granted;
    }
    Access {
        allowed: matches!(
            settings.authorization_status,
            AuthorizationStatus::Authorized
                | AuthorizationStatus::Provisional
                | AuthorizationStatus::Ephemeral
        ),
        may_request: settings.authorization_status == AuthorizationStatus::NotDetermined,
        sound: settings.sound_enabled == NotificationSettingStatus::Enabled,
    }
}

#[cfg(windows)]
pub(super) async fn access(identifier: &str, _prompt: bool) -> Access {
    use windows::{
        UI::Notifications::{NotificationSetting, ToastNotificationManager},
        core::HSTRING,
    };
    let allowed = ToastNotificationManager::CreateToastNotifierWithId(&HSTRING::from(identifier))
        .and_then(|notifier| notifier.Setting())
        .is_ok_and(|setting| setting == NotificationSetting::Enabled);
    Access {
        allowed,
        may_request: false,
        sound: allowed,
    }
}

#[cfg(target_os = "linux")]
pub(super) async fn access(_identifier: &str, _prompt: bool) -> Access {
    Access {
        allowed: true,
        may_request: false,
        sound: true,
    }
}

pub(super) fn post(
    identifier: &str,
    alert: &Alert,
    sound: TaskAlertSound,
    custom: Option<PathBuf>,
    activate: impl FnOnce(SidebarChatKey) + Send + 'static,
) -> Result<(), Box<dyn Error>> {
    let mut notification = notify_rust::Notification::new();
    notification
        .appname("Codex GUI")
        .summary(alert.title)
        .body(&alert.body)
        .timeout(12_000);
    #[cfg(windows)]
    notification.app_id(identifier);
    #[cfg(not(windows))]
    let _ = identifier;
    #[cfg(target_os = "linux")]
    notification.action("default", "Open Chat");
    #[cfg(not(target_os = "linux"))]
    notification.action("open", "Open Chat");
    sound_policy(&mut notification, sound, custom.as_ref());
    let posted = notification.show()?;
    #[cfg(any(windows, target_os = "macos"))]
    if sound == TaskAlertSound::Custom
        && let Some(path) = custom
    {
        std::thread::spawn(move || {
            if let Err(error) = play_custom(path) {
                eprintln!("{error}");
            }
        });
    }
    let owner = alert.key.clone();
    posted.wait_for_action(move |action| {
        if matches!(action, "default" | "open") {
            activate(owner);
        }
    });
    Ok(())
}

#[cfg(target_os = "macos")]
fn sound_policy(
    notification: &mut notify_rust::Notification,
    sound: TaskAlertSound,
    _custom: Option<&PathBuf>,
) {
    let sound = match sound {
        TaskAlertSound::Default => "",
        TaskAlertSound::Classic => "Sosumi.aiff",
        TaskAlertSound::Basso => "Basso.aiff",
        TaskAlertSound::Glass => "Glass.aiff",
        TaskAlertSound::Ping => "Ping.aiff",
        TaskAlertSound::Pop => "Pop.aiff",
        TaskAlertSound::Purr => "Purr.aiff",
        TaskAlertSound::Tink => "Tink.aiff",
        TaskAlertSound::Custom | TaskAlertSound::None => return,
    };
    notification.sound_name(sound);
}

#[cfg(windows)]
fn sound_policy(
    notification: &mut notify_rust::Notification,
    sound: TaskAlertSound,
    _custom: Option<&PathBuf>,
) {
    let sound = match sound {
        TaskAlertSound::Default => "Default",
        TaskAlertSound::Classic | TaskAlertSound::Basso => "Reminder",
        TaskAlertSound::Glass | TaskAlertSound::Tink => "Mail",
        TaskAlertSound::Ping | TaskAlertSound::Pop => "IM",
        TaskAlertSound::Purr => "SMS",
        TaskAlertSound::Custom | TaskAlertSound::None => return,
    };
    notification.sound_name(sound);
}

#[cfg(target_os = "linux")]
fn sound_policy(
    notification: &mut notify_rust::Notification,
    sound: TaskAlertSound,
    custom: Option<&PathBuf>,
) {
    use notify_rust::Hint;
    match sound {
        TaskAlertSound::None => {
            notification.hint(Hint::SuppressSound(true));
        }
        TaskAlertSound::Custom => {
            if let Some(path) = custom.filter(|path| path.is_file()) {
                notification.hint(Hint::SoundFile(path.to_string_lossy().into_owned()));
            } else {
                notification.hint(Hint::SuppressSound(true));
            }
        }
        TaskAlertSound::Default => {
            notification.sound_name("message-new-instant");
        }
        TaskAlertSound::Classic | TaskAlertSound::Basso => {
            notification.sound_name("complete");
        }
        TaskAlertSound::Glass | TaskAlertSound::Tink => {
            notification.sound_name("message");
        }
        TaskAlertSound::Ping | TaskAlertSound::Pop => {
            notification.sound_name("dialog-information");
        }
        TaskAlertSound::Purr => {
            notification.sound_name("service-login");
        }
    }
}

#[cfg(any(windows, target_os = "macos"))]
fn play_custom(path: PathBuf) -> Result<(), Box<dyn Error>> {
    use codex_gui_core::notifications::sound::AlertAudio;
    use rodio::{DeviceSinkBuilder, Player, buffer::SamplesBuffer};
    use std::num::{NonZeroU16, NonZeroU32};
    let audio = AlertAudio::read(&path)?;
    let sink = DeviceSinkBuilder::open_default_sink()?;
    let player = Player::connect_new(sink.mixer());
    let channels = NonZeroU16::new(audio.channels).ok_or("invalid custom sound channels")?;
    let rate = NonZeroU32::new(audio.sample_rate).ok_or("invalid custom sound rate")?;
    let samples = audio
        .samples
        .into_iter()
        .map(|sample| f32::from(sample) / 32768.0)
        .collect::<Vec<_>>();
    player.append(SamplesBuffer::new(channels, rate, samples));
    player.sleep_until_end();
    Ok(())
}
