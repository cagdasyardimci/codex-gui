import Foundation
import Testing

@testable import CodexGUI

extension ApplicationStateTests
{

	@Test func readingAnotherThreadsHistoryWhileOwnerCommandStreamsKeepsBothContents() async throws
	{
		let project = try await makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let service = MockCodexService()
		let other = try #require(
			ThreadSummary(json: [
				"id": "thread-2",
				"name": "Other",
				"cwd": project.path,
			])
		)
		service.otherThread = other
		let defaultsFixture = try IsolatedUserDefaultsFixture(prefix: "CodexGUIStateTests")
		defer
		{
			defaultsFixture.cleanup()
		}
		let state = WorkspaceTestFixture(
			server: service,
			storage: LocalStorage(defaults: defaultsFixture.defaults)
		)
		await state.inputs.connect()
		service.configureCheckout(project)
		state.inputs.openProject(project)
		state.inputs.selectThread(service.thread.id)
		await awaitSubmissionReadiness(state)
		try #require(state.currentSnapshot.canSend)
		state.inputs.updateDraft("Work on A")
		state.inputs.send()
		try #require(await service.awaitReadiness
		{
			service.turnStartCount == 1
		})
		service.emit(.turnStarted(
			threadId: service.thread.id,
			turn: service.nextTurn
		))
		let command = try #require(
			CodexItem(json: [
				"id": "command-a",
				"type": "commandExecution",
				"status": "inProgress",
				"command": "check-a",
				"cwd": project.path,
			])
		)
		service.emit(
			.itemStarted(
				threadId: service.thread.id,
				turnId: service.nextTurn.id,
				item: command
			)
		)
		service.suspendNextRead = true
		state.inputs.selectThread(other.id)
		try #require(await service.awaitReadiness
		{
			service.pendingRead != nil
		})
		service.emit(
			.commandOutputDelta(
				threadId: service.thread.id,
				turnId: service.nextTurn.id,
				itemId: command.id,
				text: "A continues working"
			)
		)
		let history = makeTurn(
			id: "b-history",
			status: "completed",
			items: [
				["id": "b-answer", "type": "agentMessage", "text": "Earlier decision in B"]
			]
		)
		service.pendingRead?.resume(
			returning: ThreadDetail(
				summary: other,
				turns: [history],
				nextTurnsCursor: nil
			)
		)
		service.pendingRead = nil
		#expect(
			await awaitApplicationStateCondition(state)
			{
				state.currentSnapshot.entries.contains
				{
					$0.body == "Earlier decision in B"
				}
			}
		)
		#expect(state.currentSnapshot.activeThreadID == nil)
		#expect(state.currentSnapshot.activeExecutionState == nil)
		#expect(state.store.model.execution(for: .thread(service.thread.id)).activeThreadID
			== service.thread.id)
		#expect(state.store.model.execution(for: .thread(service.thread.id)).activeTurnID
			== service.nextTurn.id)
		#expect(!state.currentSnapshot.entries.contains
		{
			$0.body.contains("A continues working")
		})
		state.inputs.selectThread(service.thread.id)
		#expect(state.currentSnapshot.entries.contains
		{
			$0.body.contains("A continues working")
		})
	}

}
