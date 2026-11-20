use serde_json::{Value, json};
use tempfile::tempdir;

use super::*;
use crate::storage::open_workspace_database;

fn swift_document(path: &str, version: u64) -> Value {
    let mut document: Value = serde_json::from_str(include_str!("appkit-v1.json")).unwrap();
    document["projectPath"] = json!(path);
    document["version"] = json!(version);
    document
}

#[test]
fn candidate_imports_preserve_source_bytes_and_existing_destination_context() {
    assert_eq!(
        appkit_file_name("/tmp/AppKit project café"),
        "4b68cf9cb00e4e067667230a8eb4a00c2b58bd2b2e9ea176ea4ebb459c448098.json"
    );
    let scratch = tempdir().unwrap();
    let stage = scratch.path().join("copied context");
    let checkout_path = scratch.path().join("Café project");
    fs::create_dir(&stage).unwrap();
    fs::create_dir(&checkout_path).unwrap();
    let checkout = CheckoutIdentity::capture(&checkout_path).unwrap();
    let path = checkout.canonical_path().to_str().unwrap();
    let file = stage.join(appkit_file_name(path));
    let source = serde_json::to_vec_pretty(&swift_document(path, 1)).unwrap();
    fs::write(&file, &source).unwrap();
    let database_path = scratch.path().join("tauri.sqlite3");
    let mut database = open_workspace_database(&database_path).unwrap();
    assert_eq!(
        import_appkit_project_context(&mut database, &stage, &checkout).unwrap(),
        ProjectContextImport::Imported
    );
    drop(database);

    let mut database = open_workspace_database(&database_path).unwrap();
    let imported = read_project_context(&database, &checkout).unwrap().unwrap();
    assert_eq!(imported.items[0].title, "Café settings");
    assert!(imported.items[0].is_included);
    assert_eq!(imported.selected_prompt_id.as_deref(), Some("prompt-1"));
    assert_eq!(
        imported.saved_prompts[0].instructions,
        "Review pending changes"
    );
    assert_eq!(imported.selected_skill.unwrap().name, "reviewer");
    assert_eq!(
        imported.model_preference,
        Some(ProjectModelPreference {
            model_id: None,
            effort: None
        })
    );
    assert_eq!(imported.bookmarks[0].item_id.as_deref(), Some("item-1"));
    assert_eq!(
        imported.bookmarks[0].file_path.as_deref(),
        Some("Sources/Config.swift")
    );
    assert_eq!(
        import_appkit_project_context(&mut database, &stage, &checkout).unwrap(),
        ProjectContextImport::PreservedDestination
    );

    let revision = project_context_view(&database, &checkout)
        .unwrap()
        .unwrap()
        .revision;
    let edited = edit_project_context(&mut database, &checkout, revision, |context| {
        context.saved_prompts[0].instructions = "A newer Tauri edit".into();
        Ok(())
    })
    .unwrap();
    assert_eq!(edited.revision, revision + 1);
    assert!(matches!(
        edit_project_context(&mut database, &checkout, revision, |context| {
            context.saved_prompts.clear();
            Ok(())
        }),
        Err(ProjectContextError::StaleRevision)
    ));
    assert_eq!(
        import_appkit_project_context(&mut database, &stage, &checkout).unwrap(),
        ProjectContextImport::PreservedDestination
    );
    assert_eq!(
        read_project_context(&database, &checkout)
            .unwrap()
            .unwrap()
            .saved_prompts[0]
            .instructions,
        "A newer Tauri edit"
    );
    assert_eq!(fs::read(file).unwrap(), source);
}

#[test]
fn a_foreign_or_unsupported_document_can_be_fixed_and_retried_independently() {
    let scratch = tempdir().unwrap();
    let stage = scratch.path().join("copy");
    fs::create_dir(&stage).unwrap();
    let mut database = open_workspace_database(&scratch.path().join("work.sqlite3")).unwrap();
    let capture = |name| {
        let path = scratch.path().join(name);
        fs::create_dir(&path).unwrap();
        CheckoutIdentity::capture(&path).unwrap()
    };
    let first = capture("first");
    let second = capture("second");
    let first_path = first.canonical_path().to_str().unwrap();
    let second_path = second.canonical_path().to_str().unwrap();
    let first_file = stage.join(appkit_file_name(first_path));
    let second_file = stage.join(appkit_file_name(second_path));
    let save = |file: &Path, path, version| {
        fs::write(file, swift_document(path, version).to_string()).unwrap()
    };

    assert_eq!(
        import_appkit_project_context(&mut database, &stage, &second).unwrap(),
        ProjectContextImport::MissingSource
    );
    save(&first_file, first_path, 1);
    save(&second_file, first_path, 1);
    assert_eq!(
        import_appkit_project_context(&mut database, &stage, &first).unwrap(),
        ProjectContextImport::Imported
    );
    assert!(matches!(
        import_appkit_project_context(&mut database, &stage, &second),
        Err(ProjectContextError::WrongProject)
    ));
    save(&second_file, second_path, 2);
    assert!(matches!(
        import_appkit_project_context(&mut database, &stage, &second),
        Err(ProjectContextError::UnsupportedVersion(2))
    ));
    assert!(read_project_context(&database, &first).unwrap().is_some());
    assert!(read_project_context(&database, &second).unwrap().is_none());
    save(&second_file, second_path, 1);
    assert_eq!(
        import_appkit_project_context(&mut database, &stage, &second).unwrap(),
        ProjectContextImport::Imported
    );
    assert_eq!(
        import_appkit_project_context(&mut database, &stage, &first).unwrap(),
        ProjectContextImport::PreservedDestination
    );
}
