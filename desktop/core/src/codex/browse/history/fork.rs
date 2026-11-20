use super::*;

#[derive(Clone, Debug)]
pub enum ForkBoundary {
    Before(TurnId),
    Through(TurnId),
    SavedChat,
}

impl CodexBrowser {
    pub async fn fork_chat(
        &self,
        source: &ChatRead<ChatSummary>,
        boundary: &ForkBoundary,
        timeout: Duration,
    ) -> Result<ThreadSummary, BrowseError> {
        #[derive(Deserialize)]
        struct Response {
            thread: ThreadSummary,
        }

        self.validate_chat(source)?;
        let mut params = json!({ "threadId": source.scope.thread.0, "excludeTurns": true });
        match boundary {
            ForkBoundary::Before(turn) => params["beforeTurnId"] = json!(turn.0),
            ForkBoundary::Through(turn) => params["lastTurnId"] = json!(turn.0),
            ForkBoundary::SavedChat => params["deferGoalContinuation"] = json!(true),
        }
        let response: Response = self.read("thread/fork", params, timeout).await?;
        self.validate_chat(source)?;
        if response.thread.id.0.is_empty() || response.thread.id == source.scope.thread {
            return Err(BrowseError::WrongThread);
        }
        self.checkout()?.validate_reported(&response.thread.cwd)?;
        Ok(response.thread)
    }
}
