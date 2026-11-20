use std::{collections::VecDeque, sync::Mutex};

use super::*;

const MAX_COMPARISONS: usize = 6;
const MAX_SAVED_PATCHES: usize = 32;
const MAX_SAVED_BYTES: usize = 2 * COMPARISON_PATCH_BYTES;

#[derive(Eq, PartialEq)]
pub(super) struct ImmutableKey {
    pub(super) base: String,
    pub(super) target: String,
    pub(super) policy: [u8; 32],
}

#[derive(Default)]
pub(super) struct ComparisonCache {
    entries: VecDeque<(ImmutableKey, Arc<ReusableComparison>)>,
}

pub(super) struct ReusableComparison {
    pub(super) files: Arc<[Entry]>,
    patches: Mutex<VecDeque<CachedPatch>>,
}

struct CachedPatch {
    file: Option<ComparisonFileId>,
    bytes: Arc<[u8]>,
}

impl ComparisonCache {
    pub(super) fn get(&mut self, key: &ImmutableKey) -> Option<Arc<ReusableComparison>> {
        let position = self
            .entries
            .iter()
            .position(|(existing, _)| existing == key)?;
        let entry = self.entries.remove(position)?;
        let value = entry.1.clone();
        self.entries.push_back(entry);
        Some(value)
    }

    pub(super) fn share(
        &mut self,
        key: ImmutableKey,
        files: Arc<[Entry]>,
    ) -> Arc<ReusableComparison> {
        if let Some(existing) = self.get(&key) {
            return existing;
        }
        let value = Arc::new(ReusableComparison {
            files,
            patches: Mutex::default(),
        });
        if self.entries.len() == MAX_COMPARISONS {
            self.entries.pop_front();
        }
        self.entries.push_back((key, value.clone()));
        value
    }
}

impl ReusableComparison {
    pub(super) fn get_patch(&self, id: Option<ComparisonFileId>) -> Option<Arc<[u8]>> {
        let mut patches = self.patches.lock().expect("Git patch cache poisoned");
        let position = patches.iter().position(|patch| patch.file == id)?;
        let patch = patches.remove(position)?;
        let bytes = patch.bytes.clone();
        patches.push_back(patch);
        Some(bytes)
    }

    pub(super) fn store_patch(&self, id: Option<ComparisonFileId>, bytes: &[u8]) {
        let mut patches = self.patches.lock().expect("Git patch cache poisoned");
        if patches.iter().any(|patch| patch.file == id) {
            return;
        }
        let mut used = patches.iter().map(|patch| patch.bytes.len()).sum::<usize>();
        while patches.len() >= MAX_SAVED_PATCHES || used + bytes.len() > MAX_SAVED_BYTES {
            let Some(patch) = patches.pop_front() else {
                return;
            };
            used -= patch.bytes.len();
        }
        patches.push_back(CachedPatch {
            file: id,
            bytes: Arc::from(bytes),
        });
    }
}
