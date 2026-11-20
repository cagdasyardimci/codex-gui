use std::sync::{Arc, Mutex};

use notify::{
    Config, Event, EventKind, RecommendedWatcher, RecursiveMode, Watcher, event::ModifyKind,
};

use super::*;

const MAX_SCOPES: usize = 128;

pub struct WatchedProjectPaths {
    checkout: CheckoutIdentity,
    pending: Arc<Mutex<Changes>>,
    watcher: Option<RecommendedWatcher>,
    index: Option<ProjectPathIndex>,
}

enum Changes {
    Scopes(BTreeSet<PathBuf>),
    Rebuild,
    Restart,
}

impl Default for Changes {
    fn default() -> Self {
        Self::Scopes(BTreeSet::new())
    }
}

impl WatchedProjectPaths {
    pub fn new(checkout: CheckoutIdentity) -> Self {
        Self {
            checkout,
            pending: Arc::default(),
            watcher: None,
            index: None,
        }
    }

    pub fn search(&mut self, query: &str) -> Result<Vec<ProjectPathMatch>, FileError> {
        if query.len() > MAX_QUERY_BYTES {
            return Err(FileError::TooLarge);
        }
        self.refresh()?.search(query)
    }

    pub fn resolve(&mut self, id: ProjectPathId) -> Result<PathBuf, FileError> {
        Ok(self.refresh()?.relative_path(id)?.to_owned())
    }

    pub fn browse(
        &mut self,
        folder: Option<ProjectFolderId>,
        offset: u32,
    ) -> Result<ProjectBrowsePage, FileError> {
        self.refresh()?.browse(folder, offset)
    }

    pub fn content_candidates(&mut self) -> Result<Vec<(PathBuf, String)>, FileError> {
        Ok(self
            .refresh()?
            .entries
            .iter()
            .map(|entry| (entry.path.clone(), entry.display.clone()))
            .collect())
    }

    fn refresh(&mut self) -> Result<&ProjectPathIndex, FileError> {
        if let Err(error) = self.checkout.revalidate() {
            self.watcher = None;
            self.index = None;
            return Err(error.into());
        }
        let changes =
            std::mem::take(&mut *self.pending.lock().expect("path changes lock poisoned"));
        let attach = self.watcher.is_none() || matches!(changes, Changes::Restart);
        if attach {
            self.watcher = None;
            self.watcher = watch(self.checkout.canonical_path(), self.pending.clone()).ok();
        }
        let result = self.update(changes, attach);
        if result.is_err() {
            self.pending
                .lock()
                .expect("path changes lock poisoned")
                .rebuild();
        }
        result?;
        Ok(self.index.as_ref().expect("index after update"))
    }

    fn update(&mut self, changes: Changes, attached: bool) -> Result<(), FileError> {
        let Some(index) = &mut self.index else {
            self.index = Some(ProjectPathIndex::scan(self.checkout.clone())?);
            return Ok(());
        };
        if attached {
            return index.rebuild();
        }
        match changes {
            Changes::Scopes(scopes) if scopes.is_empty() => Ok(()),
            Changes::Scopes(scopes) => index.refresh_scopes(&scopes).or_else(|_| index.rebuild()),
            Changes::Rebuild | Changes::Restart => index.rebuild(),
        }
    }
}

fn watch(root: &Path, pending: Arc<Mutex<Changes>>) -> notify::Result<RecommendedWatcher> {
    let root = event_path(root).to_path_buf();
    let callback_root = root.clone();
    let mut watcher = RecommendedWatcher::new(
        move |event: notify::Result<Event>| {
            let mut changes = pending.lock().expect("path changes lock poisoned");
            match event {
                Ok(event) => changes.observe(&callback_root, event),
                Err(_) => *changes = Changes::Restart,
            }
        },
        Config::default().with_follow_symlinks(false),
    )?;
    watcher.watch(&root, RecursiveMode::Recursive)?;
    Ok(watcher)
}

impl Changes {
    fn rebuild(&mut self) {
        if matches!(self, Self::Scopes(_)) {
            *self = Self::Rebuild;
        }
    }

    fn observe(&mut self, root: &Path, event: Event) {
        if event.need_rescan() {
            self.rebuild();
            return;
        }
        if matches!(
            event.kind,
            EventKind::Access(_) | EventKind::Modify(ModifyKind::Data(_))
        ) {
            return;
        }
        let Self::Scopes(scopes) = self else { return };
        if event.paths.is_empty() || matches!(event.kind, EventKind::Any | EventKind::Other) {
            self.rebuild();
            return;
        }
        for path in event.paths {
            let Ok(relative) = event_path(&path).strip_prefix(root) else {
                *self = Self::Rebuild;
                return;
            };
            let Some(parent) = relative.parent() else {
                *self = Self::Rebuild;
                return;
            };
            if relative
                .components()
                .any(|component| !matches!(component, Component::Normal(_)))
            {
                *self = Self::Rebuild;
                return;
            }
            if relative.file_name().is_some_and(hidden) || !visible_directory(parent) {
                continue;
            }
            if parent.as_os_str().is_empty() {
                *self = Self::Rebuild;
                return;
            }
            if parent.ancestors().any(|ancestor| scopes.contains(ancestor)) {
                continue;
            }
            scopes.retain(|scope| !scope.starts_with(parent));
            if scopes.len() >= MAX_SCOPES {
                *self = Self::Rebuild;
                return;
            }
            scopes.insert(parent.to_path_buf());
        }
    }
}

#[cfg(unix)]
fn event_path(path: &Path) -> &Path {
    path
}

#[cfg(windows)]
fn event_path(path: &Path) -> &Path {
    dunce::simplified(path)
}

#[cfg(test)]
mod tests;
