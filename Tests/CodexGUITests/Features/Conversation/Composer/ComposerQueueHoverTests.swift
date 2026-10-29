import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct ComposerQueueHoverTests
{
	@Test func actionHoverPaintsMutedPillsAndCirclesWhilePreviewStaysTransparent() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let window = NSWindow(
				contentRect: NSRect(
					x: -2000,
					y: -2000,
					width: 640,
					height: 120
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			window.prepareForTesting()
			defer
			{
				window.close()
			}
			window.appearance = NSAppearance(named: .darkAqua)
			let row = ComposerQueueRow(message: ComposerQueueTestFixture.message("Queued input"))
			row.frame = NSRect(
				x: 20,
				y: 20,
				width: 600,
				height: 32
			)
			let queue = ComposerQueueView()
			let resume = queue.resumeButton
			resume.frame = NSRect(
				x: 20,
				y: 70,
				width: 85,
				height: 24
			)
			let host = try #require(window.contentView)
			host.addSubview(row)
			host.addSubview(resume)
			window.layoutIfNeeded()
			let event = NSEvent()
			for button in [row.steer, row.remove, row.overflow, resume]
			{
				button.mouseExited(with: event)
				let idle = try bitmap(button)
				let tint = button.contentTintColor
				let title = button.attributedTitle
				button.mouseEntered(with: event)
				let hovered = try bitmap(button)
				#expect(hovered.tiffRepresentation != idle.tiffRepresentation)
				#expect(button.contentTintColor == tint)
				#expect(button.attributedTitle == title)
				let scale = CGFloat(hovered.pixelsWide) / button.bounds.width
				let fill = try #require(hovered.colorAt(
					x: Int(4 * scale),
					y: Int(12 * scale)
				))
				#expect(abs(fill.alphaComponent - 0.08) < 0.01)
				let corner = try #require(hovered.colorAt(
					x: 0,
					y: 0
				))
				#expect(corner.alphaComponent < 0.01)
				#expect(button.frame.height == 24)
				button.mouseExited(with: event)
				#expect(try bitmap(button).tiffRepresentation == idle.tiffRepresentation)
				button.isEnabled = false
				let disabled = try bitmap(button)
				button.mouseEntered(with: event)
				#expect(try bitmap(button).tiffRepresentation == disabled.tiffRepresentation)
				button.mouseExited(with: event)
				button.isEnabled = true
			}
			row.preview.mouseExited(with: event)
			let idlePreview = try bitmap(row.preview)
			row.preview.mouseEntered(with: event)
			#expect(try bitmap(row.preview).tiffRepresentation == idlePreview.tiffRepresentation)
		}
	}

	@Test func steerTooltipRetainsReferenceAppearanceAndAnchorAcrossThemes() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let window = TranscriptPointerTestWindow(
				contentRect: NSRect(
					x: 100,
					y: 100,
					width: 640,
					height: 180
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			window.prepareForTesting()
			let row = ComposerQueueRow(message: ComposerQueueTestFixture.message("Queued input"))
			row.frame = NSRect(
				x: 20,
				y: 60,
				width: 600,
				height: 32
			)
			defer
			{
				row.steer.mouseExited(with: NSEvent()); window.close()
			}
			try #require(window.contentView).addSubview(row)
			window.orderFront(nil)
			window.layoutIfNeeded()
			window.pointerLocation = row.steer.convert(
				NSPoint(
					x: row.steer.bounds.midX,
					y: row.steer.bounds.midY
				),
				to: nil
			)
			let responder = window.firstResponder
			row.steer.mouseEntered(with: NSEvent())
			await (try #require(row.steer.tooltipTask)).value
			let panel = try #require(window.childWindows?.first)
			let surface = try #require(panel.contentView?.subviews
				.compactMap
				{
					$0 as? DesktopTooltipView
				}.first)
			#expect(surface.label.stringValue == "Submit without interrupting the model")
			#expect(surface.label.font?.pointSize == 13)
			#expect(surface.bounds.width == 257)
			#expect(surface.bounds.height == 30)
			let requiredText = try #require(surface.label.cell).cellSize(forBounds: NSRect(
				x: 0,
				y: 0,
				width: surface.label.bounds.width,
				height: .greatestFiniteMagnitude
			))
			#expect(requiredText.height <= surface.label.bounds.height)
			let anchor = window.convertToScreen(row.steer.convert(
				row.steer.bounds,
				to: nil
			))
			let body = panel.convertToScreen(surface.convert(
				surface.bounds,
				to: nil
			))
			#expect(abs(body.midX - anchor.midX) < 0.5)
			#expect(abs(body.minY - anchor.maxY - 2) < 0.1)
			#expect(panel.ignoresMouseEvents && !panel.hasShadow)
			#expect(window.firstResponder === responder)
			for name: NSAppearance.Name in [.darkAqua, .aqua]
			{
				window.appearance = NSAppearance(named: name)
				let image = try surfaceBitmap(surface)
				let scale = CGFloat(image.pixelsWide) / surface.bounds.width
				var pixel = [Int](
					repeating: 0,
					count: 4
				)
				image.getPixel(
					&pixel,
					atX: Int(10 * scale),
					y: image.pixelsHigh / 2
				)
				let expected = name == .darkAqua ? 45 : 13
				#expect(abs(pixel[0] - expected) <= 1)
				#expect(abs(pixel[1] - expected) <= 1)
				#expect(abs(pixel[2] - expected) <= 1)
			}
			row.steer.mouseExited(with: NSEvent())
			#expect(!panel.isVisible && panel.parent == nil)

		}
	}

	private func surfaceBitmap(_ view: DesktopTooltipView) throws -> NSBitmapImageRep
	{
		let backing = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: Int(view.bounds.width * 2),
			pixelsHigh: Int(view.bounds.height * 2),
			bitsPerSample: 8,
			samplesPerPixel: 4,
			hasAlpha: true,
			isPlanar: false,
			colorSpaceName: .deviceRGB,
			bytesPerRow: 0,
			bitsPerPixel: 0
		))
		let image = try #require(backing.retagging(with: .sRGB))
		let context = try #require(NSGraphicsContext(bitmapImageRep: image))
		NSGraphicsContext.saveGraphicsState()
		defer
		{
			NSGraphicsContext.restoreGraphicsState()
		}
		NSGraphicsContext.current = context
		context.cgContext.scaleBy(
			x: 2,
			y: 2
		)
		view.effectiveAppearance.performAsCurrentDrawingAppearance
		{
			view.draw(view.bounds)
		}
		return image
	}

	private func bitmap(_ view: NSView) throws -> NSBitmapImageRep
	{
		let image = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
		view.cacheDisplay(
			in: view.bounds,
			to: image
		)
		return image
	}
}
