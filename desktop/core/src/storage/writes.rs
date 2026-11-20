use std::{
    collections::{HashMap, VecDeque},
    sync::Arc,
};

use crate::checkout::CheckoutIdentity;

#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
pub struct WriteId(u64);

pub struct AcceptedWrite<Operation> {
    pub id: WriteId,
    pub checkout: CheckoutIdentity,
    pub operation: Arc<Operation>,
}

pub struct FailedWrite<Operation, Error> {
    pub write: Arc<AcceptedWrite<Operation>>,
    pub error: Error,
}

pub enum DrainState<'a, Operation, Error> {
    Pending,
    Failed(Vec<&'a FailedWrite<Operation, Error>>),
    Complete,
}

/// One coordinator owns accepted SQLite and filesystem effects for a workspace store.
pub struct DurableWrites<Operation, Error> {
    next_sequence: u64,
    checkouts: HashMap<CheckoutIdentity, CheckoutWrites<Operation, Error>>,
}

struct CheckoutWrites<Operation, Error> {
    waiting: VecDeque<Arc<AcceptedWrite<Operation>>>,
    active: Option<Arc<AcceptedWrite<Operation>>>,
    failed: Vec<FailedWrite<Operation, Error>>,
}

impl<Operation, Error> Default for CheckoutWrites<Operation, Error> {
    fn default() -> Self {
        Self {
            waiting: VecDeque::new(),
            active: None,
            failed: Vec::new(),
        }
    }
}

impl<Operation, Error> Default for DurableWrites<Operation, Error> {
    fn default() -> Self {
        Self {
            next_sequence: 0,
            checkouts: HashMap::new(),
        }
    }
}

impl<Operation, Error> DurableWrites<Operation, Error> {
    pub fn reserve(&mut self, checkout: &CheckoutIdentity, operation: Operation) -> WriteId {
        self.enqueue(checkout, Arc::new(operation))
    }

    fn enqueue(&mut self, checkout: &CheckoutIdentity, operation: Arc<Operation>) -> WriteId {
        let id = WriteId(self.next_sequence);
        self.next_sequence = self
            .next_sequence
            .checked_add(1)
            .expect("workspace write sequence exhausted");
        let write = Arc::new(AcceptedWrite {
            id,
            checkout: checkout.clone(),
            operation,
        });
        self.checkouts
            .entry(checkout.clone())
            .or_default()
            .waiting
            .push_back(write);
        id
    }

    /// Dispatches each checkout's oldest eligible write. Other checkouts can run independently.
    pub fn dispatch_next(&mut self) -> Option<Arc<AcceptedWrite<Operation>>> {
        let writes = self
            .checkouts
            .values_mut()
            .filter(|writes| writes.active.is_none() && !writes.waiting.is_empty())
            .min_by_key(|writes| writes.waiting.front().map(|write| write.id))?;
        let write = writes.waiting.pop_front()?;
        writes.active = Some(write.clone());
        Some(write)
    }

    pub fn finish(
        &mut self,
        checkout: &CheckoutIdentity,
        id: WriteId,
        outcome: Result<(), Error>,
    ) -> bool {
        let Some(writes) = self.checkouts.get_mut(checkout) else {
            return false;
        };
        if writes.active.as_ref().map(|write| write.id) != Some(id) {
            return false;
        }
        let write = writes.active.take().expect("active write was validated");
        if let Err(error) = outcome {
            writes.failed.push(FailedWrite { write, error });
        }
        if writes.waiting.is_empty() && writes.failed.is_empty() {
            self.checkouts.remove(checkout);
        }
        true
    }

    /// An explicit retry preserves the payload and takes a new place in the write order.
    pub fn retry(&mut self, checkout: &CheckoutIdentity, failed: WriteId) -> Option<WriteId> {
        let writes = self.checkouts.get_mut(checkout)?;
        let position = writes
            .failed
            .iter()
            .position(|failure| failure.write.id == failed)?;
        let failure = writes.failed.swap_remove(position);
        Some(self.enqueue(checkout, failure.write.operation.clone()))
    }

    pub fn drain(&self, checkout: Option<&CheckoutIdentity>) -> DrainState<'_, Operation, Error> {
        match checkout {
            Some(checkout) => Self::drain_writes(self.checkouts.get(checkout).into_iter()),
            None => Self::drain_writes(self.checkouts.values()),
        }
    }

    fn drain_writes<'a>(
        selected: impl Iterator<Item = &'a CheckoutWrites<Operation, Error>> + Clone,
    ) -> DrainState<'a, Operation, Error>
    where
        Operation: 'a,
        Error: 'a,
    {
        if selected
            .clone()
            .any(|writes| writes.active.is_some() || !writes.waiting.is_empty())
        {
            return DrainState::Pending;
        }
        let mut failures: Vec<_> = selected.flat_map(|writes| &writes.failed).collect();
        if failures.is_empty() {
            return DrainState::Complete;
        }
        failures.sort_unstable_by_key(|failure| failure.write.id);
        DrainState::Failed(failures)
    }
}

#[cfg(test)]
mod tests;
