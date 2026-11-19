use serde::Deserialize;
use uuid::Uuid;

use crate::checkout::CheckoutIdentity;

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub struct CheckoutSessionId(pub Uuid);

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub struct ConnectionGeneration(pub u64);

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub struct RequestId(pub Uuid);

#[derive(Clone, Debug, Deserialize, Eq, Hash, PartialEq)]
pub struct ThreadId(pub String);

#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct TurnId(pub String);

#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct WorkspaceIdentity {
    pub session: CheckoutSessionId,
    /// An unselected source session has no checkout. It still requires an exact match.
    pub checkout: Option<CheckoutIdentity>,
}

#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct ConnectionIdentity {
    pub workspace: WorkspaceIdentity,
    pub generation: ConnectionGeneration,
}

/// The captured request owner remains stable as Codex assigns thread and turn IDs.
#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct OperationIdentity {
    pub connection: ConnectionIdentity,
    pub request: RequestId,
}

impl OperationIdentity {
    pub fn accepts_result(&self, active_connection: &ConnectionIdentity, result: &Self) -> bool {
        self == result && &self.connection == active_connection
    }
}

#[cfg(test)]
mod tests {
    use tempfile::{TempDir, tempdir};

    use super::*;

    fn captured_request() -> (TempDir, OperationIdentity) {
        let directory = tempdir().unwrap();
        let captured = OperationIdentity {
            connection: ConnectionIdentity {
                workspace: WorkspaceIdentity {
                    session: CheckoutSessionId(Uuid::from_u128(1)),
                    checkout: Some(CheckoutIdentity::capture(directory.path()).unwrap()),
                },
                generation: ConnectionGeneration(1),
            },
            request: RequestId(Uuid::from_u128(2)),
        };
        (directory, captured)
    }

    #[test]
    fn opening_the_same_checkout_in_a_new_session_invalidates_old_results() {
        let (_directory, captured) = captured_request();
        assert!(captured.accepts_result(&captured.connection, &captured));

        let mut reopened = captured.connection.clone();
        reopened.workspace.session = CheckoutSessionId(Uuid::from_u128(3));

        assert!(!captured.accepts_result(&reopened, &captured));
    }

    #[test]
    fn reconnect_rejects_a_result_from_the_previous_generation() {
        let (_directory, captured) = captured_request();
        let mut reconnected = captured.connection.clone();
        reconnected.generation = ConnectionGeneration(2);

        assert!(!captured.accepts_result(&reconnected, &captured));
    }

    #[test]
    fn another_request_cannot_complete_the_captured_operation() {
        let (_directory, captured) = captured_request();
        let mut result = captured.clone();
        result.request = RequestId(Uuid::from_u128(4));

        assert!(!captured.accepts_result(&captured.connection, &result));
    }

    #[test]
    fn selecting_a_checkout_retires_results_from_the_unselected_state() {
        let (_directory, mut captured) = captured_request();
        let selected = captured.connection.clone();
        captured.connection.workspace.checkout = None;
        assert!(captured.accepts_result(&captured.connection, &captured));

        assert!(!captured.accepts_result(&selected, &captured));
    }
}
