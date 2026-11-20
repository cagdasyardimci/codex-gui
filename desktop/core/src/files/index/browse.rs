use super::*;

const PAGE_SIZE: usize = 80;

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ProjectFolderId {
    anchor: ProjectPathId,
    depth: u16,
}

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct ProjectFolder {
    id: ProjectFolderId,
    name: String,
}

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub enum ProjectBrowseEntry {
    Folder(ProjectFolder),
    File(ProjectPathMatch),
}

#[derive(Debug, Serialize, TS)]
#[serde(rename_all = "camelCase")]
pub struct ProjectBrowsePage {
    revision: Uuid,
    entries: Vec<ProjectBrowseEntry>,
    next_offset: Option<u32>,
}

impl ProjectPathIndex {
    pub(super) fn browse(
        &self,
        folder: Option<ProjectFolderId>,
        offset: u32,
    ) -> Result<ProjectBrowsePage, FileError> {
        self.checkout.revalidate()?;
        let mut parent = PathBuf::new();
        let mut depth = 0;
        if let Some(folder) = folder {
            let path = self.relative_path(folder.anchor)?;
            depth = folder.depth as usize;
            if depth == 0 || depth >= path.components().count() {
                return Err(FileError::InvalidHandle);
            }
            parent.extend(path.components().take(depth));
        }
        let mut seen = 0;
        let mut last_folder = None;
        let mut entries = Vec::new();
        let mut next_offset = None;
        for (index, file) in self.entries.iter().enumerate() {
            let Ok(relative) = file.path.strip_prefix(&parent) else {
                continue;
            };
            let mut components = relative.iter();
            let Some(name) = components.next() else {
                continue;
            };
            let directory = components.next().is_some();
            if directory && last_folder == Some(name) {
                continue;
            }
            last_folder = directory.then_some(name);
            seen += 1;
            if seen <= offset {
                continue;
            }
            if entries.len() == PAGE_SIZE {
                next_offset = Some(seen - 1);
                break;
            }
            if directory {
                entries.push(ProjectBrowseEntry::Folder(ProjectFolder {
                    id: ProjectFolderId {
                        anchor: ProjectPathId {
                            revision: self.revision,
                            entry: index as u32,
                        },
                        depth: (depth + 1) as u16,
                    },
                    name: name.to_string_lossy().into_owned(),
                }));
            } else {
                entries.push(ProjectBrowseEntry::File(self.result(index)));
            }
        }
        Ok(ProjectBrowsePage {
            revision: self.revision,
            entries,
            next_offset,
        })
    }
}

#[cfg(test)]
mod tests {
    use std::fs;

    use super::*;

    #[test]
    fn paging_groups_directories_and_checks_the_captured_index_revision() {
        let directory = tempfile::tempdir().unwrap();
        let root = directory.path();
        for index in 0..81 {
            fs::write(root.join(format!("file-{index:02}.txt")), b"").unwrap();
        }
        fs::create_dir(root.join("nested")).unwrap();
        for file in ["alpha.txt", "beta.txt"] {
            fs::write(root.join("nested").join(file), b"").unwrap();
        }
        let checkout = CheckoutIdentity::capture(root).unwrap();
        let index = ProjectPathIndex::scan(checkout.clone()).unwrap();
        let first = index.browse(None, 0).unwrap();
        assert_eq!(first.entries.len(), PAGE_SIZE);
        let remaining = index.browse(None, first.next_offset.unwrap()).unwrap();
        let [
            ProjectBrowseEntry::File(file),
            ProjectBrowseEntry::Folder(folder),
        ] = remaining.entries.as_slice()
        else {
            panic!("The second page must hold the final file and one directory");
        };
        assert_eq!(file.display_path, "file-80.txt");
        assert_eq!(folder.name, "nested");
        assert_eq!(remaining.next_offset, None);
        let nested = index.browse(Some(folder.id), 0).unwrap();
        assert_eq!(nested.entries.len(), 2);
        let replaced = ProjectPathIndex::scan(checkout).unwrap();
        assert!(matches!(
            replaced.browse(Some(folder.id), 0),
            Err(FileError::InvalidHandle)
        ));
    }
}
