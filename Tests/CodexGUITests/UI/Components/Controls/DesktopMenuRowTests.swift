import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct DesktopMenuRowTests
{
	@Test func enabledPressRoutesOnceAndSelectionRemainsOwnedByTheMenu()
	{
		_ = NSApplication.shared
		let row = DesktopMenuRow(content: .init(
			title: "Optional effort",
			indicator: .checkbox
		))
		var selected = false
		var invocations = 0
		row.onInvoke =
		{
			[weak row] in
			invocations += 1
			selected.toggle()
			row?.checked = selected
		}
		#expect(row.accessibilityPerformPress())
		#expect(invocations == 1)
		#expect(row.checked)
		row.suffix = "Available"
		#expect(row.checked)
		#expect(row.accessibilityValue() as? String == "Selected")

		row.isEnabled = false
		#expect(!row.accessibilityPerformPress())
		#expect(invocations == 1)
		#expect(row.checked)

		row.isEnabled = true
		#expect(row.accessibilityPerformPress())
		#expect(invocations == 2)
		#expect(!row.checked)
		#expect(row.accessibilityValue() as? String == "Not selected")
	}

	@Test func detailedRowsReserveTrailingActionsAndRelayoutWhenContentChanges()
	{
		_ = NSApplication.shared
		let row = DesktopMenuRow(content: .init(
			title: "A model with a long descriptive name",
			icon: DesktopIcons.image(.settings),
			subtitle: "Description of the model",
			suffix: "⌘,",
			suffixStyle: .shortcut,
			indicator: .checkmark,
			checked: true
		))
		row.frame = NSRect(
			x: 0,
			y: 0,
			width: 240,
			height: row.rowHeight
		)
		row.layoutSubtreeIfNeeded()
		#expect(row.iconView.frame.maxX < row.titleLabel.frame.minX)
		#expect(row.titleLabel.frame.maxX < row.suffixLabel.frame.minX)
		#expect(row.suffixLabel.frame.maxX < row.trailingImageView.frame.minX)
		#expect(row.titleLabel.frame.maxY <= row.subtitleLabel.frame.minY)
		#expect(!row.trailingImageView.isHidden)

		row.content.subtitle = nil
		row.content.suffix = ""
		row.content.indicator = .submenu
		row.frame.size.height = row.rowHeight
		row.layoutSubtreeIfNeeded()
		#expect(row.subtitleLabel.isHidden)
		#expect(row.suffixLabel.isHidden)
		#expect(row.opensSubmenu)
		#expect(row.titleLabel.frame.maxX < row.trailingImageView.frame.minX)
		#expect(row.titleLabel.frame.maxY <= row.bounds.maxY)
	}
}
