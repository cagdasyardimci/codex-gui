import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct DesktopSearchPanelTests
{
	@Test func chatSearchShowsReadableResultsAndRestoresFocus() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let navigation = NavigationViewController()
			let window = makeWindow(controller: navigation)
			defer
			{
				navigation.searchPopover.close()
				window.close()
			}
			navigation.threads = try (0 ..< 35).map
			{
				try #require(ThreadSummary(json: [
					"id": "chat-\($0)",
					"name": "Review search panel layout \($0)",
					"cwd": "/tmp/codex-gui",
				]))
			}
			navigation.filterThreads()
			window.makeKeyAndOrderFront(nil)
			window.makeFirstResponder(navigation.searchButton)
			navigation.focusSearch()
			let field = navigation.searchField
			let panel = try #require(field.window)
			#expect(navigation.searchPopover.isShown)
			#expect(panel.parent === window)
			try verifyViewport(
				field: field,
				width: 520,
				height: 480
			)
			let content = try #require(panel.contentView)
			let scroll = try #require(descendants(content)
				.compactMap
				{
					$0 as? NSScrollView
				}.first)
			#expect(scroll.frame.height > 300)
			let document = try #require(scroll.documentView)
			#expect(document.frame.height > scroll.contentSize.height)
			let heading = try #require(descendants(document).compactMap
			{
				$0 as? NSTextField
			}.first
			{
				$0.stringValue == "Chats"
			})
			#expect(scroll.documentVisibleRect.contains(heading.convert(
				heading.bounds,
				to: document
			)))
			try capture(
				panel,
				name: "chat-light"
			)
			var chosen: String?
			navigation.onSelectThread =
			{
				chosen = $0
			}
			for appearance: NSAppearance.Name in [.darkAqua, .aqua]
			{
				window.appearance = NSAppearance(named: appearance)
				panel.contentView?.layoutSubtreeIfNeeded()
				if appearance == .darkAqua
				{
					try capture(
						panel,
						name: "chat-dark"
					)
				}
				#expect(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == appearance)
				try verifyViewport(
					field: field,
					width: 520,
					height: 480
				)
			}
			window.setContentSize(NSSize(
				width: 460,
				height: 360
			))
			NotificationCenter.default.post(
				name: NSWindow.didResizeNotification,
				object: window
			)
			#expect(panel.frame.width == 436)
			#expect(panel.frame.height == 336)
			try capture(
				panel,
				name: "chat-narrow"
			)
			#expect(navigation.control(
				field,
				textView: NSTextView(),
				doCommandBy: #selector(NSResponder.moveDown(_:))
			))
			navigation.filterThreads()
			#expect(navigation.control(
				field,
				textView: NSTextView(),
				doCommandBy: #selector(NSResponder.insertNewline(_:))
			))
			#expect(chosen == "chat-1")
			#expect(!navigation.searchPopover.isShown)
			#expect(window.firstResponder === navigation.searchButton)
			navigation.focusSearch()
			field.stringValue = "not present"
			navigation.controlTextDidChange(Notification(
				name: NSControl.textDidChangeNotification,
				object: field
			))
			let labels = descendants(try #require(panel.contentView))
				.compactMap
				{
					$0 as? NSTextField
				}
			#expect(labels.contains
			{
				$0.stringValue == "No matching conversations"
			})
			try capture(
				panel,
				name: "chat-empty"
			)
		}
	}

	private func makeWindow(controller: NSViewController) -> NSWindow
	{
		_ = NSApplication.shared
		let window = NSWindow(
			contentRect: NSRect(
				x: 50,
				y: 50,
				width: 800,
				height: 660
			),
			styleMask: [.titled, .resizable],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		window.appearance = NSAppearance(named: .aqua)
		window.contentViewController = controller
		window.setContentSize(NSSize(
			width: 800,
			height: 660
		))
		window.contentView?.layoutSubtreeIfNeeded()
		return window
	}

	private func verifyViewport(
		field: NSSearchField,
		width: CGFloat,
		height: CGFloat
	) throws
	{
		let panel = try #require(field.window)
		let content = try #require(panel.contentView)
		content.layoutSubtreeIfNeeded()
		#expect(content.bounds.width == width)
		#expect(content.bounds.height == height)
		#expect(field.frame.width >= width - 40)
		#expect(field.frame
			.height == (field.accessibilityLabel() == "Search changed files" ? 20 : 32))
		#expect(content.bounds.contains(field.convert(
			field.bounds,
			to: content
		)))
		#expect(!field.hasAmbiguousLayout)
		let cell = try #require(field.cell as? NSSearchFieldCell)
		let text = cell.searchTextRect(forBounds: field.bounds)
		let icon = cell.searchButtonRect(forBounds: field.bounds)
		if cell.searchButtonCell != nil
		{
			#expect(text.minX > icon.maxX)
			#expect(abs(text.midY - icon.midY) <= 0.5)
		}
		if let editor = field.currentEditor() as? NSTextView
		{
			#expect(editor.convert(
				editor.textContainerOrigin,
				to: field
			).x >= text.minX - 1)
		}
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		view.subviews.flatMap
		{
			[$0] + descendants($0)
		}
	}

	private func capture(
		_ window: NSWindow,
		name: String
	) throws
	{
		guard let directory = ProcessInfo.processInfo.environment["SEARCH_PANEL_CAPTURE_DIR"]
		else
		{
			return
		}
		let view = try #require(window.contentView)
		view.layoutSubtreeIfNeeded()
		view.displayIfNeeded()

		let url = URL(
			fileURLWithPath: directory,
			isDirectory: true
		)
		try FileManager.default.createDirectory(
			at: url,
			withIntermediateDirectories: true
		)
		try AppTestPNGWriter.write(
			view,
			to: url.appendingPathComponent(name + ".png")
		)
	}
}
