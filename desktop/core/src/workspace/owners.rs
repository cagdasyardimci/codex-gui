use std::{
    collections::HashMap,
    sync::{Arc, Mutex, MutexGuard},
};

use thiserror::Error;
use uuid::Uuid;

use crate::{
    checkout::{CheckoutError, CheckoutIdentity},
    codex::HistoryTurn,
    identity::{
        CheckoutSessionId, ConnectionGeneration, ConnectionIdentity, ThreadId, WorkspaceIdentity,
    },
    storage::attachments::{AttachmentError, AttachmentStore, ExitOwner, JournalError},
};

use super::{ExecutionSnapshot, WorkspaceEngine};

#[derive(Debug, Error)]
pub enum OwnerError {
    #[error(transparent)]
    Checkout(#[from] CheckoutError),
    #[error(transparent)]
    Storage(#[from] AttachmentError),
    #[error(transparent)]
    Journal(#[from] JournalError),
    #[error("the captured checkout runtime has retired")]
    Retired,
    #[error("the checkout still owns execution or accepted writes")]
    Busy,
}

#[derive(Clone)]
pub struct RuntimeOwners {
    store: AttachmentStore,
    scopes: Arc<Mutex<HashMap<CheckoutIdentity, Scope>>>,
}

#[derive(Default)]
struct Scope {
    runtime: Option<WorkspaceEngine>,
    uses: usize,
    cleanup: bool,
    recovering: Option<CheckoutSessionId>,
    retired: Vec<ExecutionSnapshot>,
}

pub struct RuntimeUse {
    owners: RuntimeOwners,
    checkout: CheckoutIdentity,
}

pub struct CleanupReservation {
    owners: RuntimeOwners,
    checkout: CheckoutIdentity,
}

pub struct RecoveryScope {
    owners: RuntimeOwners,
    connection: ConnectionIdentity,
}

impl RuntimeOwners {
    pub fn new(store: AttachmentStore) -> Self {
        Self {
            store,
            scopes: Arc::default(),
        }
    }

    pub fn register(&self, engine: WorkspaceEngine) -> Result<(), OwnerError> {
        let state = engine.snapshot();
        let checkout = checkout_of(&state.connection)?;
        checkout.revalidate()?;
        let mut scopes = self.lock();
        let scope = scopes.entry(checkout.clone()).or_default();
        if scope.cleanup || scope.runtime.is_some() {
            return Err(OwnerError::Busy);
        }
        scope.recovering = None;
        scope.runtime = Some(engine);
        Ok(())
    }

    pub fn retire(&self, owner: &ConnectionIdentity) -> Result<(), OwnerError> {
        let checkout = checkout_of(owner)?;
        let mut scopes = self.lock();
        let scope = scopes.get_mut(checkout).ok_or(OwnerError::Retired)?;
        let engine = scope.match_runtime(owner)?;
        let execution = &engine.snapshot().execution;
        scope.runtime = None;
        if let Err(error) = self.store.preserve_exit_executions(checkout, execution) {
            scope.retired.push(execution.clone());
            return Err(error.into());
        }
        prune(&mut scopes, checkout);
        Ok(())
    }

    pub fn acquire(&self, owner: &ConnectionIdentity) -> Result<RuntimeUse, OwnerError> {
        let checkout = checkout_of(owner)?;
        checkout.revalidate()?;
        let mut scopes = self.lock();
        let scope = scopes.get_mut(checkout).ok_or(OwnerError::Retired)?;
        scope.match_runtime(owner)?;
        self.acquire_scope(checkout, scope)
    }

    /// A local edit already bound to a checkout can drain after its connection retires.
    pub fn acquire_write(&self, checkout: &CheckoutIdentity) -> Result<RuntimeUse, OwnerError> {
        let mut scopes = self.lock();
        let scope = scopes.entry(checkout.clone()).or_default();
        self.acquire_scope(checkout, scope)
    }

    fn acquire_scope(
        &self,
        checkout: &CheckoutIdentity,
        scope: &mut Scope,
    ) -> Result<RuntimeUse, OwnerError> {
        if scope.cleanup {
            return Err(OwnerError::Busy);
        }
        scope.uses += 1;
        Ok(RuntimeUse {
            owners: self.clone(),
            checkout: checkout.clone(),
        })
    }

    pub fn reserve_cleanup(
        &self,
        checkout: &CheckoutIdentity,
    ) -> Result<CleanupReservation, OwnerError> {
        checkout.revalidate()?;
        let mut scopes = self.lock();
        if scopes.get(checkout).is_some_and(Scope::busy) || self.has_durable_work(checkout)? {
            return Err(OwnerError::Busy);
        }
        scopes.entry(checkout.clone()).or_default().cleanup = true;
        Ok(CleanupReservation {
            owners: self.clone(),
            checkout: checkout.clone(),
        })
    }

    pub fn exit_owners(&self) -> Result<Vec<ExitOwner>, OwnerError> {
        Ok(self.store.exit_owners()?)
    }

    pub fn has_local_work(&self, checkout: Option<&CheckoutIdentity>) -> bool {
        self.lock().iter().any(|(owner, scope)| {
            checkout.is_none_or(|checkout| checkout == owner) && (scope.uses > 0 || scope.cleanup)
        })
    }

    pub fn thread_in_use(
        &self,
        checkout: &CheckoutIdentity,
        thread: &ThreadId,
    ) -> Result<bool, OwnerError> {
        let local_execution = |execution: &ExecutionSnapshot| {
            execution
                .active_turns
                .iter()
                .any(|target| &target.thread == thread)
                || execution
                    .unresolved_commands
                    .iter()
                    .any(|command| &command.target.thread == thread)
        };
        let scopes = self.lock();
        let busy = scopes.get(checkout).is_some_and(|scope| {
            scope.uses > 0
                || scope.cleanup
                || scope.recovering.is_some()
                || scope.retired.iter().any(local_execution)
                || scope
                    .runtime
                    .as_ref()
                    .is_some_and(|runtime| local_execution(&runtime.snapshot().execution))
        });
        Ok(busy
            || self.store.has_exit_evidence(checkout, Some(thread))?
            || !self
                .store
                .pending_queue_submissions(checkout, thread)?
                .is_empty())
    }

    pub fn record_execution(
        &self,
        owner: &ConnectionIdentity,
        before: &ExecutionSnapshot,
    ) -> Result<(), OwnerError> {
        let checkout = checkout_of(owner)?;
        let scopes = self.lock();
        let runtime = scopes
            .get(checkout)
            .ok_or(OwnerError::Retired)?
            .match_runtime(owner)?;
        self.store
            .record_execution_transition(checkout, before, &runtime.snapshot().execution)?;
        Ok(())
    }

    pub fn persist_running(&self) -> Result<(), OwnerError> {
        let scopes = self.lock();
        for (checkout, scope) in &*scopes {
            if let Some(runtime) = &scope.runtime {
                self.store
                    .preserve_exit_executions(checkout, &runtime.snapshot().execution)?;
            }
        }
        Ok(())
    }

    pub fn reconcile_history(
        &self,
        owner: &ConnectionIdentity,
        thread: &ThreadId,
        history: &[HistoryTurn],
    ) -> Result<bool, OwnerError> {
        let checkout = checkout_of(owner)?;
        let scopes = self.lock();
        scopes
            .get(checkout)
            .ok_or(OwnerError::Retired)?
            .match_runtime(owner)?;
        self.store
            .reconcile_exit_history(checkout, thread, history)?;
        Ok(self.store.has_exit_evidence(checkout, Some(thread))?)
    }

    pub fn begin_recovery(
        &self,
        checkout: CheckoutIdentity,
    ) -> Result<Option<RecoveryScope>, OwnerError> {
        checkout.revalidate()?;
        let mut scopes = self.lock();
        let scope = scopes.entry(checkout.clone()).or_default();
        if scope.runtime.is_some() || scope.recovering.is_some() || scope.cleanup {
            return Ok(None);
        }
        let session = CheckoutSessionId(Uuid::new_v4());
        scope.recovering = Some(session);
        Ok(Some(RecoveryScope {
            owners: self.clone(),
            connection: ConnectionIdentity {
                workspace: WorkspaceIdentity {
                    session,
                    checkout: Some(checkout),
                },
                generation: ConnectionGeneration(1),
            },
        }))
    }

    pub fn persist_retired(&self) -> Result<(), OwnerError> {
        let mut scopes = self.lock();
        for (checkout, scope) in &mut *scopes {
            for execution in &scope.retired {
                self.store.preserve_exit_executions(checkout, execution)?;
            }
            scope.retired.clear();
        }
        scopes.retain(|_, scope| !scope.is_empty());
        Ok(())
    }

    fn lock(&self) -> MutexGuard<'_, HashMap<CheckoutIdentity, Scope>> {
        self.scopes.lock().expect("runtime ownership lock poisoned")
    }

    fn has_durable_work(&self, checkout: &CheckoutIdentity) -> Result<bool, OwnerError> {
        Ok(self.store.has_exit_evidence(checkout, None)?
            || !self.store.pending_submissions(checkout)?.is_empty())
    }
}

impl Scope {
    fn match_runtime(&self, owner: &ConnectionIdentity) -> Result<&WorkspaceEngine, OwnerError> {
        self.runtime
            .as_ref()
            .filter(|runtime| &runtime.snapshot().connection == owner)
            .ok_or(OwnerError::Retired)
    }

    fn busy(&self) -> bool {
        self.cleanup || self.has_work()
    }

    fn has_work(&self) -> bool {
        self.uses > 0
            || self.recovering.is_some()
            || !self.retired.is_empty()
            || self.runtime.as_ref().is_some_and(|runtime| {
                let snapshot = runtime.snapshot();
                !snapshot.execution.active_turns.is_empty()
                    || !snapshot.execution.unresolved_commands.is_empty()
            })
    }

    fn is_empty(&self) -> bool {
        !self.busy() && self.runtime.is_none()
    }
}

impl CleanupReservation {
    pub fn checkout(&self) -> &CheckoutIdentity {
        &self.checkout
    }

    pub(crate) fn revalidate(&self) -> Result<(), OwnerError> {
        self.checkout.revalidate()?;
        let scopes = self.owners.lock();
        let scope = scopes
            .get(&self.checkout)
            .filter(|scope| scope.cleanup)
            .ok_or(OwnerError::Retired)?;
        if scope.has_work() || self.owners.has_durable_work(&self.checkout)? {
            return Err(OwnerError::Busy);
        }
        Ok(())
    }
}

impl RecoveryScope {
    pub fn identity(&self) -> &ConnectionIdentity {
        &self.connection
    }

    /// Returns whether this thread still has unresolved exit evidence.
    pub fn reconcile(
        &self,
        thread: &ThreadId,
        history: &[HistoryTurn],
    ) -> Result<bool, OwnerError> {
        let checkout = checkout_of(&self.connection)?;
        let scopes = self.owners.lock();
        if !scopes
            .get(checkout)
            .is_some_and(|scope| scope.recovering == Some(self.connection.workspace.session))
        {
            return Err(OwnerError::Retired);
        }
        self.owners
            .store
            .reconcile_exit_history(checkout, thread, history)?;
        Ok(self
            .owners
            .store
            .has_exit_evidence(checkout, Some(thread))?)
    }
}

impl Drop for RuntimeUse {
    fn drop(&mut self) {
        let mut scopes = self.owners.lock();
        if let Some(scope) = scopes.get_mut(&self.checkout) {
            scope.uses -= 1;
        }
        prune(&mut scopes, &self.checkout);
    }
}

impl Drop for CleanupReservation {
    fn drop(&mut self) {
        let mut scopes = self.owners.lock();
        if let Some(scope) = scopes.get_mut(&self.checkout) {
            scope.cleanup = false;
        }
        prune(&mut scopes, &self.checkout);
    }
}

impl Drop for RecoveryScope {
    fn drop(&mut self) {
        let Ok(checkout) = checkout_of(&self.connection) else {
            return;
        };
        let mut scopes = self.owners.lock();
        if let Some(scope) = scopes.get_mut(checkout)
            && scope.recovering == Some(self.connection.workspace.session)
        {
            scope.recovering = None;
        }
        prune(&mut scopes, checkout);
    }
}

fn checkout_of(owner: &ConnectionIdentity) -> Result<&CheckoutIdentity, OwnerError> {
    owner.workspace.checkout.as_ref().ok_or(OwnerError::Retired)
}

fn prune(scopes: &mut HashMap<CheckoutIdentity, Scope>, checkout: &CheckoutIdentity) {
    if scopes.get(checkout).is_some_and(Scope::is_empty) {
        scopes.remove(checkout);
    }
}

#[cfg(test)]
mod tests;
