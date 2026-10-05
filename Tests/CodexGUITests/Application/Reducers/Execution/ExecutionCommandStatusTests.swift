import Foundation
import Testing

@testable import CodexGUI

@MainActor
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
		#expect(model.execution.commandLifetime.hasPendingCommands)
		#expect(model.execution.activeActivity == "printf fixture")
		try observeCommand(
			status: status,
			context: context,
			model: &model
		)
		#expect(!model.execution.commandLifetime.hasPendingCommands)
		#expect(model.execution.activeActivity == nil)
		#expect(model.execution.activeTurnID == "turn")
		#expect(model.execution.state == .running)
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
		#expect(model.execution.commandLifetime.hasPendingCommands)
		#expect(model.execution.activeActivity == "printf fixture")
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
		#expect(!model.execution.commandLifetime.hasPendingCommands)
		#expect(model.execution.activeActivity == "printf fixture")
	}

	private func fixture() -> (WorkspaceModel, OperationContext)
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/command-status"
		))
		model.connection.isConnected = true
		model.connection.generation = 1
		model.execution.state = .running
		model.execution.activeThreadID = "worker"
		model.execution.activeTurnID = "turn"
		let context = OperationContext(
			workspace: model.identity,
			generation: 1,
			requestID: UUID(),
			threadID: "worker",
			turnID: "turn"
		)
		model.execution.owner = ExecutionOwner(submission: context)
		return (model, context)
	}

	private func observeCommand(
		status: String?,
		itemType: String = "commandExecution",
		context: OperationContext,
		model: inout WorkspaceModel
	) throws
	{
		var json: [String: Any] = [
			"id": "command",
			"type": itemType,
			"command": "printf fixture"
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
