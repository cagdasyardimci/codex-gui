import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationSourcesTests
{
	@Test func readableImageLoadsThumbnailAndOpensItsCanonicalRecord() async throws
	{
		_ = NSApplication.shared
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("sources-image-\(UUID())")
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let url = directory.appendingPathComponent("preview.png")
		try DraftImageImportTestFixture.png().write(to: url)
		let sources = ConversationLocalSources(entries: [entry(
			"turn",
			images: [try reference(url.path)]
		)])
		let controller = ConversationSourcesViewController(
			owner: FeaturePresentationOwner(snapshot()),
			sources: sources
		)
		let views = descendants(controller.view)
		let button = try #require(views.compactMap
		{
			$0 as? NSButton
		}.first)
		let image = try #require(views.compactMap
		{
			$0 as? NSImageView
		}.first)
		let placeholder = image.image
		await controller.waitForPreviews()
		#expect(button.isEnabled)
		#expect(image.image != nil)
		#expect(image.image !== placeholder)
		var opened: ConversationLocalSources.Record?
		controller.onOpen =
		{
			opened = $0; return true
		}
		button.performClick(nil)
		#expect(opened == sources.records.first)
	}

	@Test func inventoryUsesOnlyUserImagesAndKeepsFirstOccurrenceOrder() throws
	{
		let first = try reference(
			"/tmp/first-source.png",
			id: "image:0"
		)
		let second = try reference(
			"/tmp/second-source.png",
			id: "image:0"
		)
		let duplicate = try reference(
			"file:///tmp/first-source.png",
			id: "image:1"
		)
		let ignored = try reference(
			"/tmp/agent-output.png",
			id: "image:0"
		)
		let sources = ConversationLocalSources(entries: [
			entry(
				"agent",
				kind: .agent,
				images: [ignored]
			),
			entry(
				"first",
				images: [first]
			),
			entry(
				"second",
				images: [duplicate, second]
			),
			entry(
				"tool",
				kind: .tool,
				images: [ignored]
			),
		])
		#expect(sources.records.map(\.path) == [first.path, second.path])
		#expect(Set(sources.records.map(\.id)).count == 2)
		#expect(sources.records.map(\.summary).map(\.detailRecordID)
			== sources.records.map
			{
				Optional($0.id)
			})
	}

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

	@Test func unavailableSourceStillShowsFilenameFullPathAndAttachmentOrigin() throws
	{
		_ = NSApplication.shared
		let path = "/tmp/missing-conversation-source-\(UUID()).png"
		let sources = ConversationLocalSources(entries: [entry(
			"turn",
			images: [try reference(path)]
		)])
		let controller = ConversationSourcesViewController(
			owner: FeaturePresentationOwner(snapshot()),
			sources: sources
		)
		let views = descendants(controller.view)
		let name = try #require(views.compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.title == URL(fileURLWithPath: path).lastPathComponent
		})
		#expect(!name.isEnabled)
		let labels = views.compactMap
		{
			$0 as? NSTextField
		}.map(\.stringValue)
		#expect(labels.contains(path))
		#expect(labels.contains("Attached to the conversation"))
		#expect(labels.contains("Image unavailable"))
	}

	@Test func sourceUpdatesKeepUnchangedViewAndShowNewAttachments() throws
	{
		_ = NSApplication.shared
		let first = try reference("/tmp/source-first-\(UUID()).png")
		let second = try reference("/tmp/source-second-\(UUID()).png")
		let sources = ConversationLocalSources(entries: [entry(
			"first",
			images: [first]
		)])
		let controller = ConversationSourcesViewController(
			owner: FeaturePresentationOwner(snapshot()),
			sources: sources
		)
		let scroll = try #require(controller.view as? NSScrollView)
		let initialDocument = try #require(scroll.documentView)
		controller.update(sources)
		#expect(scroll.documentView === initialDocument)
		controller.update(ConversationLocalSources(entries: [
			entry(
				"first",
				images: [first]
			),
			entry(
				"second",
				images: [second]
			),
		]))
		#expect(controller.sources.records.map(\.path) == [first.path, second.path])
		let labels = descendants(controller.view).compactMap
		{
			$0 as? NSButton
		}.map(\.title)
		#expect(labels.contains(first.name))
		#expect(labels.contains(second.name))
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
