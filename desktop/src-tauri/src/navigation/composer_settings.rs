use codex_gui_core::{
    ipc::{
        AccountModel, ComposerPermissions, ComposerSelection, ComposerSelectionView,
        ComposerSettingsRequest,
    },
    workspace::SendSettings,
};
use serde_json::{Value, json};

use super::*;

#[derive(Default)]
pub(super) struct ConfiguredRun {
    model: Option<String>,
    effort: Option<String>,
    tier: Option<String>,
    approval: Option<Value>,
    reviewer: Option<String>,
    sandbox: Option<Value>,
}

pub(super) async fn read_configured_run(client: AppServerClient) -> ConfiguredRun {
    let cwd = client
        .identity()
        .workspace
        .checkout
        .as_ref()
        .and_then(|checkout| checkout.canonical_path().to_str());
    let Ok(response) = client
        .request(
            "config/read",
            json!({"includeLayers": false, "cwd": cwd}),
            RPC_TIMEOUT,
        )
        .await
    else {
        return ConfiguredRun::default();
    };
    let config = &response["config"];
    let sandbox = match config["sandbox_mode"].as_str() {
        Some("read-only") => Some(json!({"type": "readOnly", "networkAccess": false})),
        Some("workspace-write") => Some(json!({ "type": "workspaceWrite",
            "networkAccess": config["sandbox_workspace_write"]["network_access"].as_bool().unwrap_or(false) })),
        Some("danger-full-access") => Some(json!({"type": "dangerFullAccess"})),
        _ => None,
    };
    ConfiguredRun {
        model: config["model"].as_str().map(str::to_owned),
        effort: config["model_reasoning_effort"].as_str().map(str::to_owned),
        tier: config["service_tier"].as_str().map(str::to_owned),
        approval: (!config["approval_policy"].is_null()).then(|| config["approval_policy"].clone()),
        reviewer: config["approvals_reviewer"].as_str().map(str::to_owned),
        sandbox,
    }
}

impl Navigation {
    pub(super) fn load_composer_settings(&mut self) -> Result<(), Failure> {
        self.view.composer_settings = if let Some(current) = &self.selection {
            let selection = self
                .store
                .composer_selection(&current.checkout, self.view.selected_chat.as_deref())?
                .unwrap_or_default();
            Some(ComposerSelectionView {
                revision: Uuid::new_v4(),
                selection,
                effective_model_id: None,
            })
        } else {
            None
        };
        self.reconcile_composer_models();
        Ok(())
    }

    pub(super) fn reconcile_composer_models(&mut self) {
        let models = &self.view.account.models;
        if models.is_empty() {
            return;
        }
        let Some(view) = self.view.composer_settings.as_mut() else {
            return;
        };
        let selection = &mut view.selection;
        let previous = selection.clone();
        if selection
            .model_id
            .as_ref()
            .is_some_and(|id| !models.iter().any(|model| model.id == *id))
        {
            selection.model_id = None;
        }
        let model = effective_model(models, selection, &self.configured_run);
        if selection
            .effort
            .as_ref()
            .is_some_and(|effort| !valid_effort(model, effort))
        {
            selection.effort = None;
        }
        if selection
            .service_tier
            .as_ref()
            .is_some_and(|tier| !valid_tier(model, tier))
        {
            selection.service_tier = None;
        }
        let effective = model.map(|model| model.id.clone());
        if *selection != previous || view.effective_model_id != effective {
            view.revision = Uuid::new_v4();
        }
        view.effective_model_id = effective;
    }

    pub(super) fn change_composer_settings(
        &mut self,
        request: ComposerSettingsRequest,
    ) -> Result<(), IpcError> {
        let scope = &request.scope;
        self.require(scope.workspace_id)?;
        let current = self
            .view
            .composer_settings
            .as_ref()
            .filter(|view| view.revision == request.revision)
            .ok_or(IpcError::StaleSelection)?;
        let selection = request.selection;
        let models = &self.view.account.models;
        let model = effective_model(models, &selection, &self.configured_run);
        if self.view.selected_chat != scope.chat_id
            || self.view.draft.as_ref().map(|draft| &draft.id) != Some(&scope.draft_id)
            || selection
                .model_id
                .as_ref()
                .is_some_and(|id| !models.iter().any(|candidate| candidate.id == *id))
            || selection
                .effort
                .as_ref()
                .is_some_and(|effort| !valid_effort(model, effort))
            || selection
                .service_tier
                .as_ref()
                .is_some_and(|tier| !valid_tier(model, tier))
            || selection.permissions == ComposerPermissions::FullAccess
                && current.selection.permissions != ComposerPermissions::FullAccess
                && !request.confirm_full_access
        {
            return Err(IpcError::StaleSelection);
        }
        if selection == current.selection {
            return Ok(());
        }
        let workspace = self.selection.as_ref().ok_or(IpcError::RetiredWorkspace)?;
        self.store
            .save_composer_selection(&workspace.checkout, scope.chat_id.as_deref(), &selection)
            .map_err(|error| report(error.into()))?;
        self.view.composer_settings = Some(ComposerSelectionView {
            revision: Uuid::new_v4(),
            selection,
            effective_model_id: model.map(|model| model.id.clone()),
        });
        self.publish_navigation();
        Ok(())
    }

    pub(super) fn capture_run_settings(&self) -> SendSettings {
        let Some(view) = &self.view.composer_settings else {
            return SendSettings::default();
        };
        let choice = &view.selection;
        let configured = &self.configured_run;
        let model = effective_model(&self.view.account.models, choice, configured);
        let model_id = model
            .map(|model| model.model.clone())
            .or_else(|| configured.model.clone());
        let effort = choice
            .effort
            .clone()
            .or_else(|| {
                choice
                    .model_id
                    .is_none()
                    .then(|| configured.effort.clone())
                    .flatten()
            })
            .or_else(|| model.and_then(|model| model.default_effort.clone()));
        let tier = choice
            .service_tier
            .clone()
            .or_else(|| configured.tier.clone())
            .or_else(|| Some("default".into()));
        let (approval, reviewer, sandbox) =
            match choice.permissions {
                ComposerPermissions::Configured => (
                    Some(
                        configured
                            .approval
                            .clone()
                            .unwrap_or_else(|| json!("on-request")),
                    ),
                    Some(configured.reviewer.clone().unwrap_or_else(|| "user".into())),
                    Some(configured.sandbox.clone().unwrap_or_else(
                        || json!({"type": "workspaceWrite", "networkAccess": false}),
                    )),
                ),
                ComposerPermissions::AskForApproval => (
                    Some(json!("on-request")),
                    Some("user".into()),
                    Some(json!({"type": "workspaceWrite", "networkAccess": false})),
                ),
                ComposerPermissions::ApproveForMe => (
                    Some(json!("on-request")),
                    Some("auto_review".into()),
                    Some(json!({"type": "workspaceWrite", "networkAccess": false})),
                ),
                ComposerPermissions::FullAccess => (
                    Some(json!("never")),
                    Some("user".into()),
                    Some(json!({"type": "dangerFullAccess"})),
                ),
            };
        SendSettings {
            model: model_id,
            reasoning_effort: effort,
            service_tier: tier,
            approval_policy: approval,
            approvals_reviewer: reviewer,
            sandbox_policy: sandbox,
            collaboration_mode: None,
        }
    }
}

fn effective_model<'a>(
    models: &'a [AccountModel],
    choice: &ComposerSelection,
    configured: &ConfiguredRun,
) -> Option<&'a AccountModel> {
    if let Some(id) = &choice.model_id {
        return models.iter().find(|model| model.id == *id);
    }
    configured
        .model
        .as_ref()
        .and_then(|name| models.iter().find(|model| model.model == *name))
        .or_else(|| models.iter().find(|model| model.is_default))
}

fn valid_effort(model: Option<&AccountModel>, effort: &str) -> bool {
    model.is_some_and(|model| {
        model
            .efforts
            .iter()
            .any(|option| option.reasoning_effort == effort)
    })
}

fn valid_tier(model: Option<&AccountModel>, tier: &str) -> bool {
    tier == "default"
        || model.is_some_and(|model| model.service_tiers.iter().any(|option| option.id == tier))
}
