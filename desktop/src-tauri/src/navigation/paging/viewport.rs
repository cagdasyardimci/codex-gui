use codex_gui_core::ipc::TranscriptViewportRequest;

use super::*;

const MAX_VIEWPORT_TURNS: usize = 1024;

impl Navigation {
    pub(in crate::navigation) fn record_transcript_viewport(
        &mut self,
        request: TranscriptViewportRequest,
    ) -> Result<(), IpcError> {
        self.require(request.workspace_id)?;
        if request.protected_turns.len() > MAX_VIEWPORT_TURNS {
            return Err(IpcError::StaleSelection);
        }
        let client = self
            .backend
            .as_ref()
            .map(|backend| backend.connection.client())
            .ok_or(IpcError::StaleSelection)?;
        self.pages
            .owner
            .as_ref()
            .filter(|owner| {
                owner.workspace == request.workspace_id
                    && owner.thread.0 == request.chat_id
                    && owner.rail.scope_id() == request.rail_id
                    && &owner.connection == client.identity()
            })
            .ok_or(IpcError::StaleSelection)?;
        let mut state = self.model.lock().expect("workspace state lock poisoned");
        state.projection.set_viewport(
            request.workspace_id,
            &request.chat_id,
            request.anchor_turn,
            request.protected_turns,
        );
        Ok(())
    }
}
