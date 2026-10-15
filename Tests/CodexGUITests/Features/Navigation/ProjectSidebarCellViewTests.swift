import AppKit
import Testing

@testable import CodexGUI

@Suite(
	.serialized
) @MainActor
struct ProjectSidebarCellViewTests
{
	@Test(
		arguments: [false, true],
		[NSAppearance.Name.aqua, .darkAqua]
	)
	func existingProjectTitleFollowsInheritedAppearance(
		isCurrent: Bool,
		initialAppearance: NSAppearance.Name
	) throws
	{
		_ = NSApplication.shared

		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 280,
				height: 100
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		defer
		{
			window.close()
		}
		window.appearance = NSAppearance(named: initialAppearance)
		let content = try #require(window.contentView)
		let cell = ProjectSidebarCellView(frame: NSRect(
			x: 0,
			y: 0,
			width: 240,
			height: 30
		))
		let table = NSTableView(frame: NSRect(
			x: 0,
			y: 0,
			width: 240,
			height: 30
		))
		content.addSubview(table)
		table.headerView = nil
		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("project"))
		column.width = 240
		table.addTableColumn(column)
		let tableContent = ProjectTableContent(cell: cell)
		table.dataSource = tableContent
		table.delegate = tableContent
		table.reloadData()
		let row = try #require(table.rowView(
			atRow: 0,
			makeIfNecessary: true
		))
		_ = try #require(table.view(
			atColumn: 0,
			row: 0,
			makeIfNecessary: true
		))
		if isCurrent
		{
			table.selectRowIndexes(
				IndexSet(integer: 0),
				byExtendingSelection: false
			)
		}
		let focus = NSTextView(frame: NSRect(
			x: 0,
			y: 40,
			width: 240,
			height: 40
		))
		content.addSubview(focus)
		let expectedFocus: NSResponder = isCurrent ? table : focus
		#expect(window.makeFirstResponder(expectedFocus))

		cell.render(
			project: URL(fileURLWithPath: "/tmp/appearance-project"),
			name: "Appearance project",
			isCurrent: isCurrent,
			isExpanded: true,
			isPinned: true,
			canStartChat: true
		)
		let label = try #require(cell.textField)
		let actions = try #require(cell.subviews.compactMap
		{
			$0 as? NSStackView
		}.first)
		let event = try #require(NSEvent.enterExitEvent(
			with: .mouseEntered,
			location: .zero,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: window.windowNumber,
			context: nil,
			eventNumber: 0,
			trackingNumber: 0,
			userData: nil
		))
		cell.mouseEntered(with: event)
		content.layoutSubtreeIfNeeded()
		#expect(window.firstResponder === expectedFocus)
		let wasEmphasized = row.isEmphasized
		let titleFrame = label.frame
		let tooltip = cell.toolTip
		let accessibilityLabel = cell.accessibilityLabel()
		let image = cell.imageView?.image
		let buttons = actions.arrangedSubviews.compactMap
		{
			$0 as? NSButton
		}
		let buttonLabels = buttons.map
		{
			$0.accessibilityLabel()
		}

		let alternateAppearance: NSAppearance.Name = initialAppearance == .aqua ? .darkAqua : .aqua
		let transitions = [
			initialAppearance,
			alternateAppearance,
			initialAppearance,
			alternateAppearance,
			initialAppearance,
		]

		// The same cell stays attached; AppKit delivers inherited appearance changes itself.
		for appearanceName in transitions
		{
			window.appearance = NSAppearance(named: appearanceName)
			content.layoutSubtreeIfNeeded()
			#expect(cell.appearance == nil)
			#expect(label.appearance == nil)
			#expect(label.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == appearanceName)
			try expectTitleColor(label)
			try expectRenderedTitleColor(label)
			#expect(cell.textField === label)
			#expect(cell.window === window)
			#expect(window.firstResponder === expectedFocus)
			#expect(row.isSelected == isCurrent)
			#expect(row.isEmphasized == wasEmphasized)
			#expect(label.stringValue == "Appearance project")
			#expect(label.frame == titleFrame)
			#expect(cell.toolTip == tooltip)
			#expect(cell.accessibilityLabel() == accessibilityLabel)
			#expect(cell.imageView?.image === image)
			#expect(!actions.isHidden)
			#expect(buttons.allSatisfy
			{
				$0.isEnabled
			})
			#expect(buttons.map
			{
				$0.accessibilityLabel()
			} == buttonLabels)
		}

		cell.mouseExited(with: event)
		#expect(actions.isHidden == !isCurrent)
	}

	private func expectTitleColor(_ label: NSTextField) throws
	{
		var actual: NSColor?
		var expected: NSColor?
		label.effectiveAppearance.performAsCurrentDrawingAppearance
		{
			actual = label.textColor?.usingColorSpace(.deviceRGB)
			expected = (NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
				? AppKitColorTokens.primaryText : AppKitColorTokens.sidebarText)
				.usingColorSpace(.deviceRGB)
		}
		let resolved = try #require(actual)
		let semantic = try #require(expected)
		#expect(abs(resolved.redComponent - semantic.redComponent) < 0.01)
		#expect(abs(resolved.greenComponent - semantic.greenComponent) < 0.01)
		#expect(abs(resolved.blueComponent - semantic.blueComponent) < 0.01)
		let opacity = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 1.0 : 0.85
		#expect(abs(resolved.alphaComponent - opacity) < 0.01)
	}

	private func expectRenderedTitleColor(_ label: NSTextField) throws
	{
		let bitmap = try #require(label.bitmapImageRepForCachingDisplay(in: label.bounds))
		label.effectiveAppearance.performAsCurrentDrawingAppearance
		{
			label.cacheDisplay(
				in: label.bounds,
				to: bitmap
			)
		}
		var opaqueGlyphs: [NSColor] = []
		for y in 0 ..< bitmap.pixelsHigh
		{
			for x in 0 ..< bitmap.pixelsWide
			{
				if let color = bitmap.colorAt(
					x: x,
					y: y
				)?.usingColorSpace(.deviceRGB),
					color.alphaComponent > 0.5
				{
					opaqueGlyphs.append(color)
				}
			}
		}
		#expect(!opaqueGlyphs.isEmpty)
		guard !opaqueGlyphs.isEmpty
		else
		{
			return
		}
		let brightness = opaqueGlyphs.reduce(0.0)
		{
			$0 + $1.redComponent
		}
		/ Double(opaqueGlyphs.count)
		let isDark = label.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
		#expect(isDark ? brightness > 0.7 : brightness < 0.3)
	}
}

@MainActor
private final class ProjectTableContent: NSObject, NSTableViewDataSource, NSTableViewDelegate
{
	private let cell: ProjectSidebarCellView

	init(cell: ProjectSidebarCellView)
	{
		self.cell = cell
	}

	func numberOfRows(in tableView: NSTableView) -> Int
	{
		1
	}

	func tableView(
		_ tableView: NSTableView,
		viewFor tableColumn: NSTableColumn?,
		row: Int
	) -> NSView?
	{
		cell
	}
}
