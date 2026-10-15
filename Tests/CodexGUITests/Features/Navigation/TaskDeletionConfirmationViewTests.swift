import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite(
	.serialized
)
struct TaskDeletionConfirmationViewTests
{
	@Test func dialogMatchesTheWarningAndKeepsHorizontalActionsUnclipped() throws
	{
		_ = NSApplication.shared
		let dialog = TaskDeletionConfirmationView()
		_ = dialog.view
		dialog.view.frame.size = dialog.view.fittingSize
		dialog.view.layoutSubtreeIfNeeded()
		#expect(dialog.headingLabel.stringValue == "Delete task?")
		#expect(dialog.warningLabel.stringValue ==
			"This permanently deletes the task and its subagent tasks.\nThis cannot be undone.")
		#expect(dialog.cancelButton.title == "Cancel")
		#expect(dialog.deleteButton.title == "Delete")

		let cancelFrame = frame(
			of: dialog.cancelButton,
			in: dialog.view
		)
		let deleteFrame = frame(
			of: dialog.deleteButton,
			in: dialog.view
		)
		let headingFrame = alignmentFrame(
			of: dialog.headingLabel,
			in: dialog.view
		)
		let deleteAlignmentFrame = alignmentFrame(
			of: dialog.deleteButton,
			in: dialog.view
		)
		#expect(abs(cancelFrame.midY - deleteFrame.midY) < 1)
		#expect(cancelFrame.maxX < deleteFrame.minX)
		#expect(cancelFrame.minX > dialog.view.bounds.midX)
		let trailingInset = dialog.view.bounds.maxX - deleteAlignmentFrame.maxX
		#expect(abs(trailingInset - headingFrame.minX) < 1)

		let controls: [NSView] = [dialog.headingLabel,
									dialog.warningLabel,
									dialog.cancelButton,
									dialog.deleteButton,
									dialog.closeButton]
		for control in controls
		{
			#expect(dialog.view.bounds.contains(frame(
				of: control,
				in: dialog.view
			)))
		}
		let warningCell = try #require(dialog.warningLabel.cell)
		let requiredWarningSize = warningCell.cellSize(forBounds: dialog.warningLabel.bounds)
		#expect(requiredWarningSize.height <= dialog.warningLabel.bounds.height + 1)
		let warningFont = try #require(dialog.warningLabel.font)
		#expect(dialog.warningLabel.bounds.height >= warningFont.pointSize * 2)
		try verifyPrimaryContentAdaptsToAppearance(dialog)
		try writeEvidence(dialog)
	}

	@Test func retainedWarningRefreshesItsForegroundWithoutChangingTextOrStyle() throws
	{
		_ = NSApplication.shared
		let dialog = TaskDeletionConfirmationView()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 420,
				height: 158
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentViewController = dialog
		defer
		{
			window.close()
		}
		dialog.view.layoutSubtreeIfNeeded()
		let originalText = dialog.warningLabel.stringValue
		let originalFont = try #require(dialog.warningLabel.attributedStringValue.attribute(
			.font,
			at: 0,
			effectiveRange: nil
		) as? NSFont)
		let originalParagraph = try #require(dialog.warningLabel.attributedStringValue.attribute(
			.paragraphStyle,
			at: 0,
			effectiveRange: nil
		) as? NSParagraphStyle)
		let originalFrame = dialog.warningLabel.frame
		for name in [NSAppearance.Name.aqua, .darkAqua, .aqua, .darkAqua]
		{
			window.appearance = try #require(NSAppearance(named: name))
			dialog.view.layoutSubtreeIfNeeded()
			let text = dialog.warningLabel.attributedStringValue
			let color = try #require(text.attribute(
				.foregroundColor,
				at: 0,
				effectiveRange: nil
			) as? NSColor)
			let rgb = try #require(color.usingColorSpace(.deviceRGB))
			let expected: CGFloat = name == .darkAqua ? 153 / 255 : 147 / 255
			#expect(abs(rgb.redComponent - expected) < 0.001)
			#expect(abs(rgb.greenComponent - expected) < 0.001)
			#expect(abs(rgb.blueComponent - expected) < 0.001)
			#expect(dialog.warningLabel.stringValue == originalText)
			#expect(text.attribute(
				.font,
				at: 0,
				effectiveRange: nil
			) as? NSFont == originalFont)
			#expect(text.attribute(
				.paragraphStyle,
				at: 0,
				effectiveRange: nil
			)
				as? NSParagraphStyle == originalParagraph)
			#expect(dialog.warningLabel.frame == originalFrame)
			#expect(dialog.cancelButton.keyEquivalent == "\r")
			#expect(dialog.deleteButton.accessibilityLabel() == "Confirm task deletion")
		}
	}

	private func frame(
		of control: NSView,
		in root: NSView
	) -> NSRect
	{
		control.convert(
			control.bounds,
			to: root
		)
	}

	private func alignmentFrame(
		of control: NSView,
		in root: NSView
	) -> NSRect
	{
		control.convert(
			control.alignmentRect(forFrame: control.bounds),
			to: root
		)
	}

	private func verifyPrimaryContentAdaptsToAppearance(
		_ dialog: TaskDeletionConfirmationView
	) throws
	{
		let headingColor = try #require(dialog.headingLabel.textColor)
		let closeColor = try #require(dialog.closeButton.contentTintColor)
		for appearanceName in [NSAppearance.Name.aqua, .darkAqua]
		{
			let appearance = try #require(NSAppearance(named: appearanceName))
			let shouldUseLightForeground = appearanceName == .darkAqua
			for color in [headingColor, closeColor]
			{
				var resolvedColor: NSColor?
				appearance.performAsCurrentDrawingAppearance
				{
					resolvedColor = color.usingColorSpace(.deviceRGB)
				}
				let foreground = try #require(resolvedColor)
				let brightness =
					(foreground.redComponent + foreground.greenComponent + foreground
						.blueComponent) / 3
				#expect((brightness > 0.5) == shouldUseLightForeground)
			}
		}
	}

	private func writeEvidence(_ dialog: TaskDeletionConfirmationView) throws
	{
		guard let directory = ProcessInfo.processInfo.environment["CODEX_GUI_UI_EVIDENCE_DIRECTORY"]
		else
		{
			return
		}
		let output = URL(fileURLWithPath: directory)
		try FileManager.default.createDirectory(
			at: output,
			withIntermediateDirectories: true
		)
		for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)]
		{
			dialog.view.appearance = NSAppearance(named: appearance)
			dialog.view.layoutSubtreeIfNeeded()
			let bitmap = try #require(dialog.view
				.bitmapImageRepForCachingDisplay(in: dialog.view.bounds))
			dialog.view.cacheDisplay(
				in: dialog.view.bounds,
				to: bitmap
			)
			let png = try #require(bitmap.representation(
				using: .png,
				properties: [:]
			))
			try png.write(to: output.appendingPathComponent("task-deletion-\(name).png"))
		}
	}
}
