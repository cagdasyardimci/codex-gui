import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct ConversationHistoryReferencesTests
{
	private let projectPath = "/Users/Shared/codex-reference-fixture"

	@Test func initializedHistoryRetainsReferenceOrderPathsAndExactNames()
	{
		let name = "Cafe\u{301}.swift"
		let turns = [turn(
			"first",
			contents: [
				mention(
					name,
					path: projectPath + "/" + name
				),
				image("/tmp/retained.png"),
				mention(
					"outside",
					path: projectPath + "-other/outside.swift"
				),
			]
		)]
		let value = model(turns: turns)
		let items = candidates(value)
		#expect(items.map(\.kind) == [.fileReference, .image])
		#expect(items.map(\.path) == [name, "/tmp/retained.png"])
		#expect(items.map(\.id) == ["first-user:0", "first-user:1"])
		#expect(Array(items[0].title.utf8) == Array(name.utf8))
	}

	@Test func canonicalArrayEditsRefreshReferencesWithoutChangingRetainedContent()
	{
		var content = ConversationContentModel()
		content.loadedTurns = [turn(
			"first",
			contents: [image("/tmp/first.png")]
		)]
		let retained = content
		content.loadedTurns.append(turn(
			"second",
			contents: [image("/tmp/second.png")]
		))
		#expect(content.loadedUserReferences?.map(\.path) == [
			"/tmp/first.png",
			"/tmp/second.png",
		])
		content.loadedTurns[0] = turn(
			"replaced",
			contents: [image("/tmp/replaced.png")]
		)
		#expect(content.loadedUserReferences?.map(\.path) == [
			"/tmp/replaced.png",
			"/tmp/second.png",
		])
		content.loadedTurns.removeAll()
		#expect(content.loadedUserReferences?.isEmpty == true)
		#expect(retained.loadedUserReferences?.map(\.path) == ["/tmp/first.png"])
	}

	@Test func cachedHistoryRemainsScopedToTheSelectedConversation()
	{
		var value = model(turns: [])
		var first = ConversationContentModel()
		first.loadedTurns = [turn(
			"shared",
			contents: [image("/tmp/first.png")]
		)]
		var second = ConversationContentModel()
		second.loadedTurns = [turn(
			"shared",
			contents: [image("/tmp/second.png")]
		)]
		value.conversations.content[.thread("first")] = first
		value.conversations.content[.thread("second")] = second
		#expect(candidates(value).map(\.path) == ["/tmp/first.png"])
		value.conversations.selectedConversation = .thread("second")
		#expect(candidates(value).map(\.path) == ["/tmp/second.png"])
		value.conversations.selectedConversation = .newChat
		#expect(candidates(value).isEmpty)
	}

	private func model(turns: [CodexTurn]) -> WorkspaceModel
	{
		var value = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: projectPath
		))
		value.conversations.selectedConversation = .thread("first")
		value.conversations.content[.thread("first")] = ConversationContentModel(loadedTurns: turns)
		return value
	}

	private func candidates(_ model: WorkspaceModel) -> [ComposerContextItem]
	{
		WorkspaceSelectors(
			model: model,
			now: .distantPast
		).reusableReferenceCandidates
	}

	private func turn(
		_ id: String,
		contents: [[String: Any]]
	) -> CodexTurn
	{
		CodexTurn(
			id: id,
			status: "completed",
			items: [CodexItem(json: [
				"id": id + "-user",
				"type": "userMessage",
				"content": contents,
			])!],
			error: nil
		)
	}

	private func mention(
		_ name: String,
		path: String
	) -> [String: Any]
	{
		["type": "mention", "name": name, "path": path]
	}

	private func image(_ path: String) -> [String: Any]
	{
		["type": "localImage", "path": path]
	}
}
