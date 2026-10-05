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
		let bitmap = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: 4,
			pixelsHigh: 4,
			bitsPerSample: 8,
			samplesPerPixel: 4,
			hasAlpha: true,
			isPlanar: false,
			colorSpaceName: .deviceRGB,
			bytesPerRow: 0,
			bitsPerPixel: 0
		))
		for x in 0 ..< 4
		{
			for y in 0 ..< 4
			{
				bitmap.setColor(
					.systemBlue,
					atX: x,
					y: y
				)
			}
		}
		try #require(bitmap.representation(
			using: .png,
			properties: [:]
		)).write(to: url)
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

	@Test func disclosureSurvivesUpdatesAndResetsForANewOwner() throws
	{
		_ = NSApplication.shared
		let controller = PinnedSummaryViewController()
		var sections = sourceSections(count: 4)
		var snapshot = snapshot()
		controller.render(PinnedSummaryPresentation(
			snapshot,
			sections: sections
		))
		#expect(try disclosure(controller).title == "Sources")
		#expect(sourceNameLabels(controller).count == 3)
		try disclosure(controller).performClick(nil)
		#expect(try disclosure(controller).title == "Sources · 4")
		#expect(sourceNameLabels(controller).isEmpty)
		#expect(!descendants(controller.view).compactMap
		{
			$0 as? NSButton
		}
		.contains
		{
			$0.title == "View all"
		})
		sections = sourceSections(count: 5)
		controller.render(PinnedSummaryPresentation(
			snapshot,
			sections: sections
		))
		#expect(try disclosure(controller).title == "Sources · 5")
		#expect(sourceNameLabels(controller).isEmpty)
		try disclosure(controller).performClick(nil)
		#expect(try disclosure(controller).title == "Sources")
		#expect(sourceNameLabels(controller).count == 3)
		try disclosure(controller).performClick(nil)
		snapshot.workspaceSelectionEpoch += 1
		controller.render(PinnedSummaryPresentation(
			snapshot,
			sections: sections
		))
		#expect(try disclosure(controller).title == "Sources")
		#expect(sourceNameLabels(controller).count == 3)
	}

	@Test func addSourceControlRemainsVisibleAndDisabledInBothStates() throws
	{
		_ = NSApplication.shared
		let controller = PinnedSummaryViewController()
		controller.render(PinnedSummaryPresentation(
			snapshot(),
			sections: sourceSections(count: 1)
		))
		let expandedAdd = try addSourceControl(controller)
		#expect(!expandedAdd.isEnabled)
		#expect(!expandedAdd.isHiddenOrHasHiddenAncestor)
		try disclosure(controller).performClick(nil)
		let collapsedAdd = try addSourceControl(controller)
		#expect(!collapsedAdd.isEnabled)
		#expect(!collapsedAdd.isHiddenOrHasHiddenAncestor)
	}

	@Test func sourcesDetailFillsInspectorAndRetainsItsViewWhenReopened() throws
	{
		_ = NSApplication.shared
		let snapshot = snapshot()
		let owner = FeaturePresentationOwner(snapshot)
		let sources = ConversationLocalSources(entries: [entry(
			"turn",
			images: try (0 ..< 12).map
			{
				try reference(
					"/tmp/sources-fixture/attachment-\($0).png",
					id: "image:\($0)"
				)
			}
		)])
		var sections = ContextSummarySections()
		sections.sources = .available(sources.records.map(\.summary))
		sections.availableDestinations.insert(.sources)
		let inspector = InspectorViewController()
		inspector.renderSummary(
			PinnedSummaryPresentation(
				snapshot,
				sections: sections
			),
			visible: true
		)
		let controller = ConversationSourcesViewController(
			owner: owner,
			sources: sources
		)
		inspector.panels.register(
			controller,
			for: .sources,
			onRequest: controller.select
		)
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 500,
				height: 700
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentViewController = inspector
		window.setContentSize(NSSize(
			width: 500,
			height: 700
		))
		defer
		{
			window.close()
		}
		window.layoutIfNeeded()
		inspector.view.layoutSubtreeIfNeeded()
		try captureIfRequested(
			inspector.view,
			name: "sources-expanded"
		)
		try disclosure(inspector.summary).performClick(nil)
		window.layoutIfNeeded()
		inspector.view.layoutSubtreeIfNeeded()
		try captureIfRequested(
			inspector.view,
			name: "sources-collapsed"
		)
		let request = ContextPanelRequest(
			owner: owner,
			destination: .sources
		)
		#expect(inspector.open(request))
		window.layoutIfNeeded()
		inspector.view.layoutSubtreeIfNeeded()
		#expect(inspector.isShowingDetails)
		#expect(inspector.summary.view.isHidden)
		#expect(inspector.panels.view.frame.height > 600)
		let scroll = try #require(controller.view as? NSScrollView)
		let document = try #require(scroll.documentView)
		try captureIfRequested(
			inspector.view,
			name: "sources-detail"
		)
		let close = try #require(descendants(inspector.panels.view).compactMap
		{
			$0 as? NSButton
		}
		.first
		{
			$0.accessibilityIdentifier() == "sources-panel-close"
		})
		close.performClick(nil)
		#expect(!inspector.isShowingDetails)
		#expect(try disclosure(inspector.summary).title == "Sources · 12")
		#expect(inspector.open(request))
		#expect(scroll.documentView === document)
		#expect(inspector.panels.children.contains
		{
			$0 === controller
		})
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

	private func sourceSections(count: Int) -> ContextSummarySections
	{
		var sections = ContextSummarySections()
		sections.sources = .available((0 ..< count).map
		{
			SummarySourceReference(
				id: "source-\($0)",
				label: "source-name-\($0).png",
				kind: .attachment
			)
		})
		sections.availableDestinations.insert(.sources)
		return sections
	}

	private func disclosure(_ controller: PinnedSummaryViewController) throws -> NSButton
	{
		try #require(descendants(controller.view).compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.accessibilityIdentifier() == "pinned-summary-sources-disclosure"
		})
	}

	private func addSourceControl(_ controller: PinnedSummaryViewController) throws -> NSButton
	{
		try #require(descendants(controller.view).compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.accessibilityIdentifier() == "pinned-summary-add-sources"
		})
	}

	private func sourceNameLabels(_ controller: PinnedSummaryViewController) -> [NSTextField]
	{
		descendants(controller.view).compactMap
		{
			$0 as? NSTextField
		}.filter
		{
			$0.stringValue.hasPrefix("source-name-")
		}
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap
		{
			descendants($0)
		}
	}

	private func captureIfRequested(
		_ view: NSView,
		name: String
	) throws
	{
		guard let directory = ProcessInfo.processInfo.environment["CODEX_SOURCES_QA_DIR"]
		else
		{
			return
		}
		let destination = URL(
			fileURLWithPath: directory,
			isDirectory: true
		)
		try FileManager.default.createDirectory(
			at: destination,
			withIntermediateDirectories: true
		)
		let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
		view.cacheDisplay(
			in: view.bounds,
			to: bitmap
		)
		let data = try #require(bitmap.representation(
			using: .png,
			properties: [:]
		))
		try data.write(to: destination.appendingPathComponent(name + ".png"))
	}
}
