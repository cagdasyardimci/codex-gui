use std::{
    env,
    path::{Path, PathBuf},
};

use codex_gui_core::ipc::{FileEditor, IpcError};
use tokio::process::Command;

enum Launcher {
    #[cfg(target_os = "macos")]
    Bundle(PathBuf),
    Executable(PathBuf),
}

pub(super) struct Editor {
    pub id: &'static str,
    label: &'static str,
    launcher: Launcher,
    directory_flag: Option<&'static str>,
}

impl Editor {
    pub fn view(&self) -> FileEditor {
        FileEditor {
            id: self.id.into(),
            label: self.label.into(),
        }
    }

    pub fn launch(&self, file: &Path) -> Result<(), IpcError> {
        let mut command = match &self.launcher {
            #[cfg(target_os = "macos")]
            Launcher::Bundle(application) => {
                let mut open = Command::new("/usr/bin/open");
                open.arg("-a").arg(application);
                open
            }
            Launcher::Executable(program) => Command::new(program),
        };
        if let Some(flag) = self.directory_flag {
            if !flag.is_empty() {
                command.arg(flag);
            }
            command.arg(file.parent().ok_or(IpcError::ProjectUnavailable)?);
        } else {
            command.arg(file);
        }
        let mut process = command.spawn().map_err(|_| IpcError::ProjectUnavailable)?;
        tauri::async_runtime::spawn(async move {
            let _ = process.wait().await;
        });
        Ok(())
    }
}

pub(super) fn installed() -> Vec<Editor> {
    #[cfg(target_os = "macos")]
    let definitions = [
        ("vscode", "VS Code", "code", "Visual Studio Code.app", None),
        ("zed", "Zed", "zed", "Zed.app", None),
        ("terminal", "Terminal", "", "Terminal.app", Some("")),
        ("kitty", "Kitty", "kitty", "kitty.app", Some("")),
        ("xcode", "Xcode", "", "Xcode.app", None),
    ];
    #[cfg(windows)]
    let definitions = [
        (
            "vscode",
            "VS Code",
            "Code.exe",
            "Programs/Microsoft VS Code/Code.exe",
            None,
        ),
        ("zed", "Zed", "zed.exe", "Programs/Zed/zed.exe", None),
        (
            "terminal",
            "Windows Terminal",
            "wt.exe",
            "Microsoft/WindowsApps/wt.exe",
            Some("-d"),
        ),
        ("notepad", "Notepad", "notepad.exe", "", None),
    ];
    #[cfg(not(any(target_os = "macos", windows)))]
    let definitions = [
        ("vscode", "VS Code", "code", "", None),
        ("zed", "Zed", "zed", "", None),
        ("kitty", "Kitty", "kitty", "", Some("--directory")),
    ];

    definitions
        .into_iter()
        .filter_map(|(id, label, command, known, directory_flag)| {
            let launcher = find(command, known)?;
            Some(Editor {
                id,
                label,
                launcher,
                directory_flag,
            })
        })
        .collect()
}

fn find(command: &str, known: &str) -> Option<Launcher> {
    #[cfg(target_os = "macos")]
    {
        let mut directories = vec![
            PathBuf::from("/Applications"),
            PathBuf::from("/System/Applications"),
            PathBuf::from("/System/Applications/Utilities"),
        ];
        if let Some(home) = env::var_os("HOME") {
            directories.push(PathBuf::from(home).join("Applications"));
        }
        if let Some(bundle) = directories
            .into_iter()
            .map(|parent| parent.join(known))
            .find(|path| path.is_dir())
        {
            return Some(Launcher::Bundle(bundle));
        }
    }
    #[cfg(windows)]
    if !known.is_empty() {
        let local = env::var_os("LOCALAPPDATA")
            .map(PathBuf::from)
            .map(|parent| parent.join(known));
        let global = env::var_os("ProgramFiles")
            .filter(|_| command == "Code.exe")
            .map(PathBuf::from)
            .map(|parent| parent.join("Microsoft VS Code").join(command));
        if let Some(program) = local
            .into_iter()
            .chain(global)
            .find(|path| is_executable(path))
        {
            return Some(Launcher::Executable(program));
        }
    }
    #[cfg(not(any(target_os = "macos", windows)))]
    let _ = known;
    if command.is_empty() {
        return None;
    }
    env::var_os("PATH")
        .and_then(|path| {
            env::split_paths(&path)
                .filter(|directory| directory.is_absolute())
                .map(|directory| directory.join(command))
                .find(|program| is_executable(program))
        })
        .map(Launcher::Executable)
}

fn is_executable(path: &Path) -> bool {
    let Ok(metadata) = path.metadata() else {
        return false;
    };
    if !metadata.is_file() {
        return false;
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        metadata.permissions().mode() & 0o111 != 0
    }
    #[cfg(not(unix))]
    true
}
