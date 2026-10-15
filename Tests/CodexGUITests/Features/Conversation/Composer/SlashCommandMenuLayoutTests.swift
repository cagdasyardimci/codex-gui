import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite(
	"Slash menu layout",
	.serialized
)
struct SlashCommandMenuLayoutTests
{
	@Test func pointerMovementAndScrollingClearPreviousHoverWithoutChangingKeyboardSelection(
	) throws
	{
		_ = NSApplication.shared
		let menu = SlashCommandPopoverView()
		menu.render(prefix: "")
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 720,
				height: 316
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentViewController = menu
		defer
		{
			window.orderOut(nil)
		}
		window.layoutIfNeeded()
		let scroll = try #require(menu.view.subviews.first?.subviews.first as? NSScrollView)
		let table = try #require(scroll.documentView as? SlashCommandMenuTableView)
		table.scrollRowToVisible(0)
		let first = try #require(table.rowView(
			atRow: 1,
			makeIfNecessary: true
		)
			as? SlashCommandMenuRowView)
		let second = try #require(table.rowView(
			atRow: 2,
			makeIfNecessary: true
		)
			as? SlashCommandMenuRowView)
		func movePointer(to row: Int) throws
		{
			let rect = table.rect(ofRow: row)
			let location = table.convert(
				NSPoint(
					x: rect.midX,
					y: rect.midY
				),
				to: nil
			)
			let event = try #require(NSEvent.mouseEvent(
				with: .mouseMoved,
				location: location,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 0,
				clickCount: 0,
				pressure: 0
			))
			table.mouseMoved(with: event)
		}
		try movePointer(to: 1)
		#expect(first.isHovered)
		#expect(!second.isHovered)
		try movePointer(to: 2)
		#expect(!first.isHovered)
		#expect(second.isHovered)
		scroll.contentView.scroll(to: NSPoint(
			x: 0,
			y: 56
		))
		scroll.reflectScrolledClipView(scroll.contentView)
		#expect(!first.isHovered)
		#expect(!second.isHovered)
		try movePointer(to: 3)
		#expect(table.hoveredRow == 3)
		#expect(menu.selectedCommand?.id == .new)
		table.refreshHover(at: nil)
		#expect(table.hoveredRow == nil)
		#expect(!first.isHovered)
		#expect(!second.isHovered)
	}

	// Shows a composer panel with application event monitors while repositioning its anchor.
	@Test func panelTracksAnchorWidthInsteadOfKeepingItsInitialPreferredWidth(
	) async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let native = TestTiming.begin("native.body")
			defer
			{
				native.end()
			}
			_ = NSApplication.shared
			let parent = NSWindow(
				contentRect: NSRect(
					x: 100,
					y: 100,
					width: 600,
					height: 400
				),
				styleMask: [.borderless],
				backing: .buffered,
				defer: false
			)
			parent.isReleasedWhenClosed = false
			let anchor = NSView(frame: NSRect(
				x: 30,
				y: 30,
				width: 430,
				height: 80
			))
			try #require(parent.contentView).addSubview(anchor)
			let menu = SlashCommandPopoverView()
			menu.render(prefix: "")
			let panel = ComposerPopoverPanel(contentViewController: menu)
			panel.matchesAnchorWidth = true
			panel.preservesParentKeyboardFocus = true
			defer
			{
				panel.close()
				parent.orderOut(nil)
			}
			panel.show(
				relativeTo: anchor.bounds,
				of: anchor
			)
			let child = try #require(parent.childWindows?.first)
			child.layoutIfNeeded()
			#expect(abs(child.frame.width - 430) < 1)
			#expect(abs(menu.view.bounds.width - 430) < 1)
			anchor.setFrameSize(NSSize(
				width: 540,
				height: 80
			))
			panel.reposition()
			child.layoutIfNeeded()
			#expect(abs(child.frame.width - 540) < 1)
			#expect(abs(menu.view.bounds.width - 540) < 1)
		}
	}

	@Test func inlineRowsStayWithinPanelInBothThemesAndSkillsUseTheSameLayout() throws
	{
		_ = NSApplication.shared
		let menu = SlashCommandPopoverView()
		menu.availableSkills = try ["Browser", "Documents", "Analytics Dashboard"].map
		{
			name in
			try #require(AvailableSkill(json: [
				"name": name.lowercased(),
				"description": "A long skill description that should truncate within the row",
				"path": "/skills/\(name)",
				"scope": "user",
				"enabled": true,
				"interface": ["displayName": name],
			]))
		}
		menu.unavailableReason =
		{
			_ in "Select a saved chat before using this command."
		}
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 720,
				height: 316
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentViewController = menu
		defer
		{
			window.orderOut(nil)
		}
		let output = ProcessInfo.processInfo.environment["CODEX_GUI_SLASH_MENU_CAPTURES"]
		for (theme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)]
		{
			window.appearance = NSAppearance(named: appearance)
			for prefix in ["", "browser"]
			{
				menu.render(prefix: prefix)
				for width: CGFloat in [430, 720]
				{
					menu.preferredContentSize.width = width
					window.setFrame(
						NSRect(
							origin: window.frame.origin,
							size: NSSize(
								width: width,
								height: menu.preferredContentSize.height
							)
						),
						display: true
					)
					window.layoutIfNeeded()
					menu.view.layoutSubtreeIfNeeded()
					#expect(abs(menu.view.bounds.width - width) < 1)
					let scroll = try #require(menu.view.subviews.first?.subviews
						.first as? NSScrollView)
					let table = try #require(scroll.documentView as? NSTableView)
					#expect(table.frame.width <= menu.view.bounds.width)
					#expect(table.style == .plain)
					let row = prefix.isEmpty ? 0 : 1
					let cell = try #require(table.view(
						atColumn: 0,
						row: row,
						makeIfNecessary: true
					))
					cell.layoutSubtreeIfNeeded()
					let contents = try #require(cell.subviews.first as? NSStackView)
					let labels = contents.arrangedSubviews.compactMap
					{
						$0 as? NSTextField
					}
					#expect(labels.count >= 2)
					#expect(abs(labels[0].frame.midY - labels[1].frame.midY) < 1)
					#expect(contents.frame.maxX <= cell.bounds.maxX)
					#expect(contents.frame.minX >= 0)
					if prefix == "browser"
					{
						let scope = try #require(labels.last)
						#expect(abs(scope.frame.maxX - contents.bounds.maxX) <= 2)
						let rowRect = table.rect(ofRow: row)
						#expect(scroll.contentView.bounds.contains(rowRect))
					}
					if let output
					{
						let directory = URL(fileURLWithPath: output)
						try FileManager.default.createDirectory(
							at: directory,
							withIntermediateDirectories: true
						)
						let bitmap = try #require(menu.view
							.bitmapImageRepForCachingDisplay(in: menu.view.bounds))
						menu.view.cacheDisplay(
							in: menu.view.bounds,
							to: bitmap
						)
						let png = try #require(bitmap.representation(
							using: .png,
							properties: [:]
						))
						try png.write(to: directory.appendingPathComponent(
							"\(theme)-\(prefix.isEmpty ? "commands" : "skills")-\(Int(width)).png"
						))
					}
				}
			}
		}
	}
}
