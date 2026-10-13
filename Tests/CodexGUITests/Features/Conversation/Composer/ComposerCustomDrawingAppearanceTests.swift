import AppKit
import QuartzCore
import Testing

@testable import CodexGUI

@MainActor
@Suite(.serialized)
struct ComposerCustomDrawingAppearanceTests
{
	@Test func retainedModelButtonRedrawsWithoutChangingHighlightedSelection() throws
	{
		let button = ModelEffortSelectionButton(frame: NSRect(
			x: 0,
			y: 0,
			width: 220,
			height: 28
		))
		button.update(
			summary: "Appearance model High",
			effortTitle: "High",
			fastMode: true,
			isPickerPresented: false
		)
		button.cell?.isHighlighted = true
		let title = button.title
		let size = button.intrinsicContentSize
		let value = button.accessibilityValue() as? String
		try verifyRetainedDrawing(button)
		{
			#expect(button.cell?.isHighlighted == true)
			#expect(button.title == title)
			#expect(button.intrinsicContentSize == size)
			#expect(button.accessibilityValue() as? String == value)
		}
	}

	@Test func retainedEffortSliderRedrawsWithoutChangingValueOrFocus() throws
	{
		let slider = EffortSlider(frame: NSRect(
			x: 0,
			y: 0,
			width: 240,
			height: 40
		))
		slider.cell = EffortSliderCell()
		slider.minValue = 0
		slider.maxValue = 3
		slider.numberOfTickMarks = 4
		slider.doubleValue = 2
		slider.ultraSelected = true
		slider.fastMode = true
		try verifyRetainedDrawing(
			slider,
			focus: true
		)
		{
			#expect(slider.doubleValue == 2)
			#expect(slider.numberOfTickMarks == 4)
			#expect(slider.ultraSelected)
			#expect(slider.fastMode)
		}
	}

	@Test(arguments: [false, true])
	func retainedSlashRowRedrawsWithoutChangingHoverOrSelection(selected: Bool) throws
	{
		let row = SlashCommandMenuRowView(frame: NSRect(
			x: 0,
			y: 0,
			width: 220,
			height: 40
		))
		row.isHovered = true
		row.isSelected = selected
		try verifyRetainedDrawing(row)
		{
			#expect(row.isHovered)
			#expect(row.isSelected == selected)
		}
	}

	@Test func retainedApprovalRowRedrawsWhileHoverSelectionAndFocusRemain() throws
	{
		let controller = ApprovalPolicyPopoverView()
		let content = controller.view
		content.frame = NSRect(
			x: 0,
			y: 0,
			width: 434,
			height: 159
		)
		controller.render(mode: .approveForMe)
		let stack = try #require(content.subviews.first?.subviews.first as? NSStackView)
		let row = try #require(stack.arrangedSubviews.compactMap
		{
			$0 as? NSButton
		}.dropFirst()
		.first)
		let event = try #require(NSEvent.mouseEvent(
			with: .mouseMoved,
			location: .zero,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			eventNumber: 0,
			clickCount: 0,
			pressure: 0
		))
		row.mouseEntered(with: event)
		try verifyRetainedDrawing(
			row,
			container: content,
			focus: true
		)
		{
			#expect(row.accessibilityValue() as? String == "Selected")
			#expect(row.accessibilityLabel() == ApprovalMode.approveForMe.title)
		}
	}

	private func verifyRetainedDrawing(
		_ view: NSView,
		container: NSView? = nil,
		focus: Bool = false,
		verifyState: () -> Void
	) throws
	{
		_ = NSApplication.shared
		let window = NSWindow(
			contentRect: NSRect(
				x: -2000,
				y: -2000,
				width: 460,
				height: 180
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.appearance = NSAppearance(named: .aqua)
		let content = try #require(window.contentView)
		view.wantsLayer = true
		content.addSubview(container ?? view)
		window.orderFront(nil)
		window.layoutIfNeeded()
		if focus
		{
			#expect(window.makeFirstResponder(view))
		}
		defer
		{
			window.close()
		}
		let frame = view.frame
		var images: [Data] = []
		for name: NSAppearance.Name in [.darkAqua, .aqua, .darkAqua, .aqua]
		{
			window.appearance = NSAppearance(named: name)
			#expect(view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == name)
			verifyState()
			#expect(view.frame == frame)
			if focus
			{
				#expect(window.firstResponder === view)
			}
			window.displayIfNeeded()
			CATransaction.flush()
			let bitmap = try renderedBacking(view)
			images.append(try #require(bitmap.representation(
				using: .png,
				properties: [:]
			)))
		}
		#expect(images[0] != images[1])
		#expect(images[0] == images[2])
		#expect(images[1] == images[3])
	}
	private func renderedBacking(_ view: NSView) throws -> NSBitmapImageRep
	{
		// Capture the retained layer after normal display, without asking the view to redraw.
		let bitmap = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: Int(view.bounds.width),
			pixelsHigh: Int(view.bounds.height),
			bitsPerSample: 8,
			samplesPerPixel: 4,
			hasAlpha: true,
			isPlanar: false,
			colorSpaceName: .deviceRGB,
			bytesPerRow: 0,
			bitsPerPixel: 0
		))
		let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
		let layer = try #require(view.layer)
		layer.render(in: context.cgContext)
		return bitmap
	}

}
