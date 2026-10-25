import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationSourcesTests
{

	@Test func selectionEpochRejectsAnObsoleteSourceRequest() throws
	{
		let sources = ConversationLocalSources(entries: [entry(
			"turn",
			images: [try reference("/tmp/source.png")]
		)])
		var snapshot = snapshot()
		let oldOwner = FeaturePresentationOwner(
			snapshot,
			storeIdentity: "store"
		)
		let request = ContextPanelRequest(
			owner: oldOwner,
			destination: .sources,
			recordID: sources.records[0].id
		)
		snapshot.workspaceSelectionEpoch += 1
		let newOwner = FeaturePresentationOwner(
			snapshot,
			storeIdentity: "store"
		)
		#expect(sources.record(
			for: request,
			owner: newOwner
		) == nil)
		#expect(sources.record(
			for: request,
			owner: oldOwner
		) == sources.records[0])
	}

	private func snapshot() -> ConversationSnapshot
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/fixture/workspace"
		))
		model.conversations.selectedConversation = .thread("sources-chat")
		return WorkspaceSelectors.snapshot(
			model: model,
			now: .distantPast
		)
	}

	private func reference(
		_ path: String,
		id: String = "image"
	) throws -> UserMessageReference
	{
		try #require(UserMessageReference(
			json: ["type": "localImage", "path": path],
			id: id
		))
	}

	private func entry(
		_ id: String,
		kind: ConversationEntryKind = .user,
		images: [UserMessageReference]
	) -> ConversationEntry
	{
		ConversationEntry(
			id: id,
			kind: kind,
			title: "You",
			body: "",
			imageAttachments: images
		)
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap
		{
			descendants($0)
		}
	}
}
