import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct ExecutionCommandStatusTests
{
	@Test(arguments: ["completed", "failed", "declined", "interrupted", "cancelled"])
	func terminalCommandEventClearsBarrierAndCurrentActivity(status: String) throws
	{
		var (model, context) = fixture()
		try observeCommand(
			status: "running",
			context: context,
			model: &model
		)
		#expect(model.executions.entries[.thread("worker")]!.commandLifetime.hasPendingCommands)
		#expect(model.executions.entries[.thread("worker")]!.activeActivity == "Running a command…")
		try observeCommand(
			status: status,
			context: context,
			model: &model
		)
		#expect(!model.executions.entries[.thread("worker")]!.commandLifetime.hasPendingCommands)
		#expect(model.executions.entries[.thread("worker")]!.activeActivity == nil)
		#expect(model.executions.entries[.thread("worker")]!.activeTurnID == "turn")
		#expect(model.executions.entries[.thread("worker")]!.state == .running)
	}

	@Test(arguments: [nil, "futureStatus", "running", "inProgress"] as [String?])
	func missingAndUnknownCommandOutcomesRetainBarrierAndActivity(status: String?) throws
	{
		var (model, context) = fixture()
		try observeCommand(
			status: status,
			context: context,
			model: &model
		)
		#expect(model.executions.entries[.thread("worker")]!.commandLifetime.hasPendingCommands)
		#expect(model.executions.entries[.thread("worker")]!.activeActivity == "Running a command…")
	}

	@Test(arguments: ["printf fixture", "python3 - <<'PY'\nfrom pathlib import Path\nPY"])
	func commandActivityUsesAShortDescription(command: String) throws
	{
		var (model, context) = fixture()
		try observeCommand(
			status: "running",
			command: command,
			context: context,
			model: &model
		)
		#expect(model.executions.entries[.thread("worker")]!.activeActivity == "Running a command…")
	}

	@Test(arguments: ["interrupted", "cancelled"])
	func mcpEventsRetainTheirIndependentActivityPolicy(status: String) throws
	{
		var (model, context) = fixture()
		try observeCommand(
			status: status,
			itemType: "mcpToolCall",
			context: context,
			model: &model
		)
		#expect(!model.executions.entries[.thread("worker")]!.commandLifetime.hasPendingCommands)
		#expect(model.executions.entries[.thread("worker")]!.activeActivity == "printf fixture")
	}

	private func fixture() -> (WorkspaceModel, OperationContext)
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/command-status"
		))
		model.connection.isConnected = true
		model.executions.entries[.thread("worker")] = ExecutionModel()
		model.connection.generation = 1
		model.executions.entries[.thread("worker")]!.state = .running
		model.executions.entries[.thread("worker")]!.activeThreadID = "worker"
		model.executions.entries[.thread("worker")]!.activeTurnID = "turn"
		let context = OperationContext(
			workspace: model.identity,
			generation: 1,
			requestID: UUID(),
			threadID: "worker",
			turnID: "turn"
		)
		model.executions.entries[.thread("worker")]!.owner = ExecutionOwner(submission: context)
		return (model, context)
	}

	private func observeCommand(
		status: String?,
		itemType: String = "commandExecution",
		command: String = "printf fixture",
		context: OperationContext,
		model: inout WorkspaceModel
	) throws
	{
		var json: [String: Any] = [
			"id": "command",
			"type": itemType,
			"command": command
		]
		if let status
		{
			json["status"] = status
		}
		let item = try #require(CodexItem(json: json))
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.backendObserved(
				context,
				.itemCompleted(
					threadId: "worker",
					turnId: "turn",
					item: item
				)
			))
		)
	}
}
