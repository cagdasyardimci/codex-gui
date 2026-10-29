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
		#expect(row.iconView.frame.maxX < row.titleLabel
			.alignmentRect(forFrame: row.titleLabel.frame).minX)
		#expect(row.titleLabel.alignmentRect(forFrame: row.titleLabel.frame).maxX < row.suffixLabel
			.alignmentRect(forFrame: row.suffixLabel.frame).minX)
		#expect(row.suffixLabel.alignmentRect(forFrame: row.suffixLabel.frame).maxX < row
			.trailingImageView.frame.minX)
		#expect(row.titleLabel.alignmentRect(forFrame: row.titleLabel.frame).maxY <= row
			.subtitleLabel.alignmentRect(forFrame: row.subtitleLabel.frame).minY)
		#expect(!row.trailingImageView.isHidden)

		row.content.subtitle = nil
		row.content.suffix = ""
		row.content.indicator = .submenu
		row.frame.size.height = row.rowHeight
		row.layoutSubtreeIfNeeded()
		#expect(row.subtitleLabel.isHidden)
		#expect(row.suffixLabel.isHidden)
		#expect(row.opensSubmenu)
		#expect(row.titleLabel.alignmentRect(forFrame: row.titleLabel.frame).maxX < row
			.trailingImageView.frame.minX)
		#expect(row.titleLabel.alignmentRect(forFrame: row.titleLabel.frame).maxY <= row.bounds
			.maxY)

		for presentation in [DesktopMenuRow.TextPresentation.standard, .aligned]
		{
			let measured = DesktopMenuRow(
				content: .init(title: "Model"),
				textPresentation: presentation
			)
			let plainWidth = measured.preferredSize.width
			measured.content.icon = DesktopIcons.image(.settings)
			measured.content.subtitle = "A longer description that must fit without truncation"
			measured.content.suffix = "Available"
			measured.content.indicator = .checkmark
			measured.frame = NSRect(
				origin: .zero,
				size: measured.preferredSize
			)
			measured.layoutSubtreeIfNeeded()
			#expect(measured.bounds.width > plainWidth)
			#expect((measured.subtitleLabel.cell?.cellSize.width ?? 0) <= measured.subtitleLabel
				.frame.width + 0.5)
			#expect((measured.suffixLabel.cell?.cellSize.width ?? 0) <= measured.suffixLabel.frame
				.width + 0.5)
			#expect(measured.subtitleLabel.alignmentRect(forFrame: measured.subtitleLabel.frame)
				.maxX < measured.suffixLabel.alignmentRect(forFrame: measured.suffixLabel.frame)
				.minX)
			#expect(measured.suffixLabel.alignmentRect(forFrame: measured.suffixLabel.frame)
				.maxX < measured.trailingImageView.frame.minX)
		}

	}
}
