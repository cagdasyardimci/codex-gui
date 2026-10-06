import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct SourcesInspectorIntegrationTests
{
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
		try AppTestPNGWriter.write(
			view,
			to: destination.appendingPathComponent(name + ".png")
		)
	}
}
