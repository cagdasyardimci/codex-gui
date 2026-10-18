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

	@Test func acceptedHistoryReplacementRemovesOldReferencesAndStreamingKeepsNewOnes()
	{
		var value = model(turns: [turn(
			"old",
			contents: [image("/tmp/old.png")]
		)])
		let summary = ThreadSummary(json: ["id": "first", "cwd": projectPath])!
		ConversationContentReducer.merge(
			ThreadDetail(
				summary: summary,
				turns: [turn(
					"new",
					contents: [image("/tmp/new.png")]
				)],
				nextTurnsCursor: nil
			),
			model: &value
		)
		ConversationContentReducer.updateContent(
			for: "first",
			model: &value
		)
		{
			$0.entries.append(ConversationEntry(
				id: "streamed",
				kind: .agent,
				title: "Assistant",
				body: "A growing response"
			))
		}
		#expect(candidates(value).map(\.path) == ["/tmp/new.png"])
		ConversationContentReducer.merge(
			ThreadDetail(
				summary: summary,
				turns: [],
				nextTurnsCursor: nil
			),
			model: &value
		)
		#expect(candidates(value).isEmpty)
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

	@Test func sentReferencesAndImageValidationStillApplyToCachedHistory()
	{
		var value = model(turns: [])
		value.conversations.content[.thread("first")]?.loadedTurns = [turn(
			"first",
			contents: [image("/tmp/sent.png"), image("/tmp/valid.png"), image("/tmp/stale.png")]
		)]
		let sent = ComposerContextItem(
			id: "sent",
			kind: .image,
			title: "Sent image",
			path: "/tmp/sent.png"
		)
		value.composer.sentReferences[.thread("first")] = [sent]
		value.lifecycle.validatedImagePaths = ["/tmp/sent.png", "/tmp/valid.png"]
		#expect(candidates(value).map(\.path) == [
			"/tmp/sent.png",
			"/tmp/valid.png",
			"/tmp/stale.png",
		])
		let snapshot = WorkspaceSelectors(
			model: value,
			now: .distantPast
		).makeSnapshot()
		#expect(snapshot.reusableReferences.map(\.path) == ["/tmp/sent.png", "/tmp/valid.png"])
		#expect(snapshot.reusableReferences.first == sent)
	}

	@Test func reusableHistoryDeduplicatesNormalizedFilesAndImagesInFirstSeenOrder()
	{
		var value = model(turns: [
			turn(
				"first",
				contents: [
					mention(
						"Sent alias",
						path: projectPath + "/Sources/Sent.swift"
					),
					mention(
						"First name",
						path: projectPath + "/Sources/New.swift"
					),
					image("/tmp/shared.png"),
				]
			),
			turn(
				"second",
				contents: [
					mention(
						"Later name",
						path: projectPath + "/Sources/New.swift"
					),
					image("/tmp/shared.png"),
					mention(
						"Last",
						path: projectPath + "/Last.swift"
					),
				]
			),
		])
		let sent = ComposerContextItem(
			id: "sent-file",
			kind: .fileReference,
			title: "Chosen title",
			path: "Sources/Sent.swift"
		)
		value.composer.sentReferences[.thread("first")] = [sent]
		let items = candidates(value)
		#expect(items.map(\.path) == [
			"Sources/Sent.swift",
			"Sources/New.swift",
			"/tmp/shared.png",
			"Last.swift",
		])
		#expect(items.first == sent)
		#expect(items.map(\.id) == ["sent-file", "first-user:1", "first-user:2", "second-user:2"])
		#expect(items[1].title == "First name")
	}

	@Test func reusableHistoryPreservesByteDistinctFilePathsBesideAnAuthoritativeSentRow()
	{
		let composed = "Café.swift"
		let decomposed = "Cafe\u{301}.swift"
		var value = model(turns: [turn(
			"first",
			contents: [
				mention(
					"Composed history",
					path: projectPath + "/" + composed
				),
				mention(
					"Decomposed history",
					path: projectPath + "/" + decomposed
				),
				mention(
					"Repeated history",
					path: projectPath + "/" + decomposed
				),
			]
		)])
		let sent = ComposerContextItem(
			id: "sent-file",
			kind: .fileReference,
			title: "Chosen title",
			path: composed
		)
		value.composer.sentReferences[.thread("first")] = [sent]
		let items = candidates(value)
		#expect(items.map(\.id) == ["sent-file", "first-user:1"])
		#expect(items.first == sent)
		#expect(items.last?.path?.utf8.elementsEqual(decomposed.utf8) == true)
		#expect(items.last?.title == "Decomposed history")
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
