import AppKit

extension MainWindowController
{
	/// Returns the incoming layout for installation after its conversation tools have rendered.
	func selectChatTools(target: WorkspaceIntentTarget) -> WindowPaneController.ToolsPaneState?
	{
		let key = ChatToolsKey(
			workspace: target.reference,
			conversation: target.store.model.executionIdentity(for: target.conversation)
		)
		guard let previous = chatToolsKey
		else
		{
			chatToolsKey = key
			return nil
		}
		let executions = target.store.model.executions
		// A draft's tabs follow the exact first-message submission when Codex assigns its ID.
		let previousKey = previous.workspace == key.workspace
			? ChatToolsKey(
				workspace: previous.workspace,
				conversation: executions.canonicalIdentity(previous.conversation)
			) : previous
		chatToolsKey = key
		guard previousKey != key
		else
		{
			return nil
		}

		pendingFileSearch = nil
		expandedSummaryPopover?.close()
		activeChatTools.pane = paneController.suspendChatTools()
		if activeChatTools.tabs.tabCount > 0 || !files.runtime.state.documents.isEmpty
		{
			parkedChatTools[previousKey] = activeChatTools
		}
		let savedKey = parkedChatTools[key] != nil ? key : parkedChatTools.keys.first
		{
			$0.workspace == key.workspace && executions.canonicalIdentity($0.conversation) ==
				key.conversation
		}
		let incoming = savedKey.flatMap
		{
			parkedChatTools.removeValue(forKey: $0)
		}
		?? ChatToolsSession()
		activeChatTools = incoming
		inspector.replaceToolsTabs(with: incoming.tabs)
		configureChatFileActions(incoming)
		configureToolsPaneClosing()
		return incoming.pane
	}

	var chatFileRuntimes: [FileViewerRuntime]
	{
		[files.runtime] + parkedChatTools.values.map
		{
			$0.files.runtime
		}
	}
}
