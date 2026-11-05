import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ToolsTabSourcesIntegrationTests
{
	@Test(.appKitIsolation)
	func selectedTabIsRevealedAfterHeaderAttachmentAndResize() throws
	{
		_ = NSApplication.shared
		let tabs = ToolsTabViewController()
		tabs.openNewTab()
		tabs.openNewTab()
		let changes = NSViewController()
		changes.view = NSView()
		tabs.showChanges(changes)
		let sources = NSViewController()
		sources.view = NSView()
		tabs.showSources(sources)
		try #require(tabs.tabCount == 3)
		let window = NSWindow(
			contentRect: NSRect(
				x: -2000,
				y: -2000,
				width: 640,
				height: 40
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		defer
		{
			window.close()
		}
		let host = try #require(window.contentView)
		AppKitLayout.pin(
			tabs.tabBarView,
			to: host,
			inset: 0
		)
		for width in [640.0, 320.0, 280.0]
		{
			window.setContentSize(NSSize(
				width: width,
				height: 40
			))
			window.layoutIfNeeded()
			host.layoutSubtreeIfNeeded()
			let selected = try #require(button(
				"Sources 3",
				in: tabs.tabBarView
			))
			let scroll = try #require(selected.enclosingScrollView)
			let document = try #require(scroll.documentView)
			let frame = selected.convert(
				selected.bounds,
				to: document
			)
			let visible = scroll.documentVisibleRect
			#expect(frame.minX >= visible.minX)
			#expect(frame.maxX <= visible.maxX)
		}
		let selected = try #require(button(
			"Sources 3",
			in: tabs.tabBarView
		))
		let scroll = try #require(selected.enclosingScrollView)
		scroll.contentView.scroll(to: .zero)
		scroll.reflectScrolledClipView(scroll.contentView)
		tabs.tabBarView.layoutSubtreeIfNeeded()
		#expect(scroll.contentView.bounds.origin.x == 0)
	}

	@Test func inspectorRejectsStaleOwnerAndRemovesSourcesTabWhenChatChanges() throws
	{
		_ = NSApplication.shared
		let inspector = InspectorViewController()
		var snapshot = snapshot()
		let presentation = PinnedSummaryPresentation(
			snapshot,
			ownerIdentity: "fixture"
		)
		inspector.renderSummary(
			presentation,
			visible: true
		)
		let sources = try sourcesController(owner: presentation.owner)
		inspector.conversationSources = sources
		let request = ContextPanelRequest(
			owner: presentation.owner,
			destination: .sources
		)
		#expect(inspector.openSourcesInToolTab(request))
		#expect(inspector.isShowingTools)
		#expect(inspector.toolsTabs.isSourcesSelected)
		#expect(!inspector.isShowingDetails)
		#expect(sources.parent === inspector.toolsTabs)
		#expect(inspector.openSourcesInToolTab(request))
		#expect(inspector.toolsTabs.tabCount == 1)
		#expect(!inspector.openSourcesInToolTab(ContextPanelRequest(
			owner: presentation.owner,
			destination: .sources,
			recordID: "missing-record"
		)))
		snapshot = self.snapshot(thread: "another-chat")
		inspector.renderSummary(
			PinnedSummaryPresentation(
				snapshot,
				ownerIdentity: "fixture"
			),
			visible: true
		)
		#expect(inspector.toolsTabs.sourcesTabID == nil)
		#expect(!inspector.openSourcesInToolTab(request))
		#expect(inspector.toolsTabs.sourcesTabID == nil)
	}

	private func snapshot(thread: String = "sources-chat") -> ConversationSnapshot
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/fixture/workspace"
		))
		model.conversations.selectedConversation = .thread(thread)
		return WorkspaceSelectors.snapshot(
			model: model,
			now: .distantPast
		)
	}

	private func sourcesController(owner: FeaturePresentationOwner? = nil) throws
		-> ConversationSourcesViewController
	{
		let image = try #require(UserMessageReference(
			json: ["type": "localImage", "path": "/tmp/sources-fixture/attached-image.png"],
			id: "image"
		))
		return ConversationSourcesViewController(
			owner: owner ?? FeaturePresentationOwner(snapshot()),
			sources: ConversationLocalSources(entries: [ConversationEntry(
				id: "turn:user",
				kind: .user,
				title: "You",
				body: "",
				imageAttachments: [image]
			)])
		)
	}

	private func button(
		_ label: String,
		in view: NSView
	) -> NSButton?
	{
		if let button = view as? NSButton, button.accessibilityLabel() == label
		{
			return button
		}
		return view.subviews.lazy.compactMap
		{
			button(
				label,
				in: $0
			)
		}.first
	}

	private func captureIfRequested(_ tabs: ToolsTabViewController) throws
	{
		guard let directory = ProcessInfo.processInfo.environment["CODEX_SOURCES_QA_DIR"]
		else
		{
			return
		}
		let host = NSViewController()
		host.view = NSView()
		let stack = AppKitLayout.verticalStack(
			[tabs.tabBarView, tabs.view],
			spacing: 8
		)
		AppKitLayout.pin(
			stack,
			to: host.view,
			inset: 12
		)
		tabs.tabBarView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		tabs.tabBarView.heightAnchor.constraint(equalToConstant: 28).isActive = true
		tabs.view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		tabs.view.bottomAnchor.constraint(equalTo: stack.bottomAnchor).isActive = true
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 900,
				height: 600
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		window.contentViewController = host
		window.setContentSize(NSSize(
			width: 900,
			height: 600
		))
		defer
		{
			window.close()
		}
		window.layoutIfNeeded()
		host.view.layoutSubtreeIfNeeded()
		let destination = URL(
			fileURLWithPath: directory,
			isDirectory: true
		)
		try FileManager.default.createDirectory(
			at: destination,
			withIntermediateDirectories: true
		)
		try AppTestPNGWriter.write(
			host.view,
			to: destination.appendingPathComponent("sources-tools-tab.png")
		)
	}
}
