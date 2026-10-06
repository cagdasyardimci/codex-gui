import Foundation
import Testing
@testable import CodexGUI

@MainActor
struct TurnReferenceTestFixture
{
	let state: WorkspaceTestFixture
	let service: MockCodexService
	let project: URL

	func close()
	{
		state.shutdown()
		service.pendingTurnContentRead?.resume(throwing: CancellationError())
		service.pendingTurnContentRead = nil
		try? FileManager.default.removeItem(at: project)
	}
}

@MainActor
func makeTurnReferenceTestFixture(
	pagedReferences: Bool = false,
	totalTurns: Int = 66,
	previewPreparer: any ConversationPreviewPreparing = ConversationMarkdownPreviewPreparer()
) async throws -> TurnReferenceTestFixture
{
	let project = FileManager.default.temporaryDirectory.appendingPathComponent(
		"TurnReferenceTests-\(UUID())",
		isDirectory: true
	)
	try FileManager.default.createDirectory(
		at: project.appendingPathComponent(".git"),
		withIntermediateDirectories: true
	)
	let service = MockCodexService()
	service.configureCheckout(project)
	let turns = (0 ..< totalTurns).map
	{
		index in
		CodexTurn(json: ["id": "turn-\(index)", "status": "completed", "items": [
			[
				"id": "request",
				"type": "userMessage",
				"content": [["type": "text", "text": "Request \(index)"]]
			],
			["id": "reply", "type": "agentMessage", "text": "Reply \(index)"],
		]])!
	}
	let references = turns.map
	{
		ConversationTurnReference(
			id: $0.id,
			status: $0.status
		)
	}
	service.savedTurns = Array(turns.suffix(25))
	service.readNextCursor = "older-content"
	service.referencedTurnContents = Dictionary(uniqueKeysWithValues: turns.map
	{
		($0.id, $0)
	})
	service.turnReferencePages[""] = TurnReferencePage(
		references: pagedReferences ? Array(references.suffix(50)) : references,
		nextCursor: pagedReferences ? "older-references" : nil
	)
	service.turnReferencePages["older-references"] = TurnReferencePage(
		references: Array(references.prefix(16)),
		nextCursor: nil
	)
	let defaults = try #require(UserDefaults(suiteName: "TurnReferenceTests.\(UUID())"))
	let state = WorkspaceTestFixture(store: WorkspaceStoreFactory.makeSource(
		dependencies: WorkspaceStoreDependencies(
			service: service,
			storage: LocalStorage(defaults: defaults),
			previewPreparer: previewPreparer
		)
	))
	await state.inputs.connect()
	state.inputs.openProject(project)
	try #require(await waitForTurnReferenceCondition
	{
		state.currentSnapshot.canManageThreads
	})
	state.inputs.selectThread(service.thread.id)
	try #require(await waitForTurnReferenceCondition
	{
		state.currentSnapshot.entries.count == 50 && state.currentSnapshot.turnReferences
			.count == (pagedReferences ? 50 : totalTurns)
	})
	return TurnReferenceTestFixture(
		state: state,
		service: service,
		project: project
	)
}

@MainActor
func waitForTurnReferenceCondition(_ predicate: @escaping @MainActor () -> Bool) async -> Bool
{
	for _ in 0 ..< 200
	{
		if predicate()
		{
			return true
		}
		try? await Task.sleep(for: .milliseconds(5))
	}
	return predicate()
}
