import AppKit
import QuartzCore
import Testing

@testable import CodexGUI

@MainActor
@Suite(
	.serialized
)
struct ComposerCustomDrawingAppearanceTests
{

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
		let row = try #require(approvalRow(
			in: content,
			mode: .approveForMe
		))
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

	private func approvalRow(
		in view: NSView,
		mode: ApprovalMode
	) -> NSButton?
	{
		if let row = view as? NSButton, row.accessibilityLabel() == mode.title
		{
			return row
		}
		return view.subviews.lazy.compactMap
		{
			approvalRow(
				in: $0,
				mode: mode
			)
		}.first
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
		window.prepareForTesting()
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
