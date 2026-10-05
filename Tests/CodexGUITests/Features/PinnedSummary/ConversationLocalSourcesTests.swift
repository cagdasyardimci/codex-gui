import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationLocalSourcesTests
{
	@Test func canonicalImagesPreserveOrderIdentityAndResolveOnlyLocalPaths() throws
	{
		let first = try #require(UserMessageReference(
			json: ["type": "localImage", "path": "/tmp/source image.png", "name": "First"],
			id: "image:0"
		))
		let duplicate = try #require(UserMessageReference(
			json: ["type": "localImage", "path": "file:///tmp/source%20image.png"],
			id: "image:0"
		))
		let remote = try #require(UserMessageReference(
			json: ["type": "localImage", "path": "https://example.com/image.png"],
			id: "image:0"
		))
		let entries = [
			ConversationEntry(
				id: "first:user",
				kind: .user,
				title: "You",
				body: "",
				imageAttachments: [first]
			),
			ConversationEntry(
				id: "second:user",
				kind: .user,
				title: "You",
				body: "",
				imageAttachments: [duplicate, remote]
			)
		]
		let inventory = ConversationLocalSources(entries: entries)
		#expect(inventory.records.count == 2)
		#expect(inventory.records[0].name == "First")
		#expect(inventory.records[0].url?.path == first.path)
		#expect(inventory.records[1].url == nil)
		#expect(inventory.records[0].id != inventory.records[1].id)
		#expect(inventory.records.map(\.id) == ConversationLocalSources(entries: entries).records
			.map(\.id))
		#expect(LocalAttachmentURL.resolve("file://remote-machine/tmp/image.png") == nil)
		#expect(LocalAttachmentURL.resolve("relative.png") == nil)
		#expect(LocalAttachmentURL.resolve("file:relative.png") == nil)
		#expect(LocalAttachmentURL.resolve("~/image.png")?.path
			.hasPrefix(NSHomeDirectory() + "/") == true)
	}

	@Test func recordNavigationRejectsForeignOwnersAndInventedRecords() throws
	{
		let reference = try #require(UserMessageReference(
			json: ["type": "localImage", "path": "/tmp/image.png"],
			id: "image"
		))
		let inventory = ConversationLocalSources(entries: [
			ConversationEntry(
				id: "turn:user",
				kind: .user,
				title: "You",
				body: "",
				imageAttachments: [reference]
			)
		])
		let snapshot = WorkspaceSelectors.snapshot(
			model: WorkspaceModel(identity: WorkspaceIdentity(
				sessionID: UUID(),
				canonicalCheckoutPath: "/tmp/project"
			)),
			now: Date()
		)
		let owner = FeaturePresentationOwner(
			snapshot,
			storeIdentity: "store"
		)
		let foreign = FeaturePresentationOwner(
			snapshot,
			storeIdentity: "other-store"
		)
		let request = ContextPanelRequest(
			owner: owner,
			destination: .sources,
			recordID: inventory.records[0].id
		)
		#expect(inventory.record(
			for: request,
			owner: owner
		) == inventory.records[0])
		#expect(inventory.record(
			for: request,
			owner: foreign
		) == nil)
		#expect(inventory.record(
			for: ContextPanelRequest(
				owner: owner,
				destination: .sources,
				recordID: "fabricated"
			),
			owner: owner
		) ==
			nil)
		#expect(inventory.record(
			for: ContextPanelRequest(
				owner: owner,
				destination: .changes,
				recordID: inventory.records[0].id
			),
			owner: owner
		) == nil)
	}

	@Test func inaccessibleFilesKeepTheirNamesAndDisableOpening() throws
	{
		_ = NSApplication.shared
		let reference = try #require(UserMessageReference(
			json: [
				"type": "localImage",
				"path": "/tmp/missing-source-\(UUID()).png",
				"name": "Missing source"
			],
			id: "image"
		))
		let inventory = ConversationLocalSources(entries: [
			ConversationEntry(
				id: "turn:user",
				kind: .user,
				title: "You",
				body: "",
				imageAttachments: [reference]
			)
		])
		let snapshot = WorkspaceSelectors.snapshot(
			model: WorkspaceModel(identity: WorkspaceIdentity(
				sessionID: UUID(),
				canonicalCheckoutPath: "/tmp/project"
			)),
			now: Date()
		)
		let controller = ConversationSourcesViewController(
			owner: FeaturePresentationOwner(snapshot),
			sources: inventory
		)
		let views = descendants(controller.view)
		let button = try #require(views.compactMap
		{
			$0 as? NSButton
		}.first)
		#expect(button.title == "Missing source")
		#expect(!button.isEnabled)
		#expect(views.compactMap
		{
			$0 as? NSTextField
		}
		.contains
		{
			$0.stringValue == "Image unavailable"
		})
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap
		{
			descendants($0)
		}
	}
}
