import Foundation

/// Test-only observation. Never dispatches actions or waits for the UI test process.
@MainActor
final class UITestEvidenceRecorder
{
	static let shared = UITestEvidenceRecorder()
	private let destination: URL?
	private let queue = DispatchQueue(label: "CodexGUI.ui-test-evidence")
	private var sequence = 0
	private var history: [Data] = []

	private init()
	{
		let path = ProcessInfo.processInfo.environment["CODEX_GUI_E2E_STATE"]
		destination = path.flatMap
		{
			$0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil
		}
	}

	func record(
		_ model: WorkspaceModel,
		action: WorkspaceAction
	)
	{
		guard let destination
		else
		{
			return
		}
		sequence += 1
		let selectors = WorkspaceSelectors(
			model: model,
			now: Date()
		)
		let executions: [[String: Any]] = model.allExecutions.map
		{
			[
				"threadID": $0.activeThreadID ?? "",
				"turnID": $0.activeTurnID ?? "",
				"state": $0.state.rawValue,
				"requestID": $0.owner?.submission.requestID.uuidString ?? "",
				"stopRequested": $0.stopRequested,
				"interruptRequestSent": $0.interruptRequestSent,
				"pendingCommands": $0.commandLifetime.hasPendingCommands,
				"uncertainRequest": $0.hasUncertainRequest,
				"pendingInteractionCount": $0.pendingInteractions.count,
			]
		}
		let value: [String: Any] = [
			"schemaVersion": 1,
			"sequence": sequence,
			"time": Date().timeIntervalSince1970,
			"uptime": ProcessInfo.processInfo.systemUptime,
			"actionFamily": actionFamily(action),
			"workspaceSessionID": model.identity.sessionID.uuidString,
			"projectPath": model.identity.canonicalCheckoutPath ?? "",
			"selectedThreadID": selectors.selectedThreadID ?? "",
			"connectionGeneration": model.connection.generation,
			"connected": model.connection.isConnected,
			"draftCharacterCount": selectors.draft.count,
			"executions": executions,
		]
		guard let data = try? JSONSerialization.data(
			withJSONObject: value,
			options: [.sortedKeys]
		)
		else
		{
			return
		}
		history.append(data)
		if history.count > 200
		{
			history.removeFirst(history.count - 200)
		}
		var output = Data("[".utf8)
		for (index, entry) in history.enumerated()
		{
			if index > 0
			{
				output.append(Data(",".utf8))
			}
			output.append(entry)
		}
		output.append(Data("]".utf8))
		let captured = output
		queue.async
		{
			do
			{
				try captured.write(
					to: destination,
					options: .atomic
				)
			}
			catch
			{
				// Collection errors are diagnostics; they cannot alter application behavior.
				fputs(
					"UI test state capture failed: \(error.localizedDescription)\n",
					stderr
				)
			}
		}
	}

	private func actionFamily(_ action: WorkspaceAction) -> String
	{
		switch action
		{
		case .workspaceLifecycle: "workspaceLifecycle"
		case .connection: "connection"
		case .remoteAccess: "remoteAccess"
		case .execution: "execution"
		case .composer: "composer"
		case .composerCommand: "composerCommand"
		case .conversations: "conversations"
		case .review: "review"
		case .contextNavigation: "contextNavigation"
		case .preferences: "preferences"
		case .usage: "usage"
		}
	}
}
