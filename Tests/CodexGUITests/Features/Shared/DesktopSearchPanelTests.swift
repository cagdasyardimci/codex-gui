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

	@Test func fileJumpShowsScrollableRowsBelowAnchorAndKeepsEmptyStateSized() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let host = NSViewController()
			host.view = DesktopSurface(AppKitColorTokens.canvas)
			let window = makeWindow(controller: host)
			let anchor = NSButton(frame: NSRect(
				x: 730,
				y: 610,
				width: 30,
				height: 30
			))
			host.view.addSubview(anchor)
			let files = (0 ..< 40).map
			{
				GitComparisonFile(
					oldPath: "docs/Reference\($0).md",
					newPath: "docs/Reference\($0).md",
					kind: .modified,
					additions: 1,
					deletions: 0,
					isBinary: false,
					patch: "",
					hunks: []
				)
			}
			let controller = GitFileJumpPopoverController(index: GitFileJumpIndex(files: files))
			let presenter = DesktopSearchPanel(
				controller: controller,
				placement: .belowAnchor,
				size: NSSize(
					width: 400,
					height: 280
				)
			)
			defer
			{
				presenter.close()
				window.close()
			}
			window.makeKeyAndOrderFront(nil)
			presenter.show(
				relativeTo: anchor.bounds,
				of: anchor
			)
			controller.focusSearch()
			let field = try #require(descendants(controller.view)
				.compactMap
				{
					$0 as? NSSearchField
				}.first)
			let icon = try #require(descendants(controller.view).compactMap
			{
				$0 as? NSImageView
			}.first)
			#expect(icon.convert(
				icon.bounds,
				to: controller.view
			).maxX
				< field.convert(
					field.bounds,
					to: controller.view
				).minX)
			let panel = try #require(field.window)
			try verifyViewport(
				field: field,
				width: 400,
				height: 280
			)
			#expect(panel.frame.maxY < window.convertToScreen(anchor.frame).minY)
			let scroll = try #require(descendants(controller.view)
				.compactMap
				{
					$0 as? NSScrollView
				}.first)
			#expect(scroll.frame.height > 200)
			let document = try #require(scroll.documentView)
			#expect(document.frame.height > scroll.contentSize.height)
			let buttons = descendants(controller.view)
				.compactMap
				{
					$0 as? DesktopSearchResultButton
				}
			#expect(buttons.count == 40)
			#expect(buttons[0].frame.width > 350)
			#expect(scroll.documentVisibleRect.intersects(
				buttons[0].convert(
					buttons[0].bounds,
					to: document
				)
			))
			for button in buttons
			{
				for label in descendants(button).compactMap(
					{
						$0 as? NSTextField
					}
				)
				{
					#expect(button.bounds.contains(label.convert(
						label.bounds,
						to: button
					)))
				}
			}
			try capture(
				panel,
				name: "jump-light"
			)
			window.appearance = NSAppearance(named: .darkAqua)
			panel.contentView?.layoutSubtreeIfNeeded()
			try capture(
				panel,
				name: "jump-dark"
			)
			field.stringValue = "absent"
			controller.controlTextDidChange(Notification(
				name: NSControl.textDidChangeNotification,
				object: field
			))
			panel.contentView?.layoutSubtreeIfNeeded()
			try verifyViewport(
				field: field,
				width: 400,
				height: 280
			)
			#expect(descendants(controller.view).compactMap
			{
				$0 as? NSTextField
			}
			.contains
			{
				$0.stringValue == "No matching files"
			})
			try capture(
				panel,
				name: "jump-empty"
			)
		}
	}

	@Test func removingAnchorOrClosingParentRetiresPanel() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let host = NSViewController()
			host.view = NSView()
			let window = makeWindow(controller: host)
			defer
			{
				window.close()
			}
			let anchor = NSButton(frame: NSRect(
				x: 20,
				y: 600,
				width: 30,
				height: 30
			))
			host.view.addSubview(anchor)
			let controller = NSViewController()
			controller.view = NSView()
			let presenter = DesktopSearchPanel(
				controller: controller,
				placement: .centered,
				size: NSSize(
					width: 520,
					height: 480
				)
			)
			defer
			{
				presenter.close()
			}
			window.makeKeyAndOrderFront(nil)
			presenter.show(
				relativeTo: anchor.bounds,
				of: anchor
			)
			#expect(presenter.isShown)
			anchor.isHidden = true
			presenter.close()
			presenter.show(
				relativeTo: anchor.bounds,
				of: anchor
			)
			#expect(!presenter.isShown)
			#expect(controller.view.window?.isVisible != true)
			anchor.isHidden = false
			presenter.show(
				relativeTo: anchor.bounds,
				of: anchor
			)
			#expect(presenter.isShown)
			anchor.removeFromSuperview()
			#expect(!presenter.isShown)
			#expect(controller.view.window?.isVisible != true)
			host.view.addSubview(anchor)
			presenter.show(
				relativeTo: anchor.bounds,
				of: anchor
			)
			#expect(presenter.isShown)
			window.close()
			#expect(!presenter.isShown)
			#expect(controller.view.window?.isVisible != true)
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
		window.isReleasedWhenClosed = false
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
