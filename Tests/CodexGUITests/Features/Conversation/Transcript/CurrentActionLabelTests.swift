import AppKit
import QuartzCore
import Testing

@testable import CodexGUI

@Suite @MainActor
struct CurrentActionLabelTests
{
	@Test func sweepMovesRightWithOutsideEndpointsAndPause() throws
	{
		for text in ["Thinking", "Running a command", "Reading a much longer file name"]
		{
			let (label, window) = makeLabel(text)
			defer
			{
				window.contentView = nil
			}
			label.actionIsActive = true
			let overlay = try #require(label.highlightLayer)
			let gradient = try #require(overlay.sublayers?.first as? CAGradientLayer)
			let sweep = try #require(gradient.animation(forKey: CurrentActionLabel.animationKey)
				as? CAKeyframeAnimation)
			let values = try #require(sweep.values as? [CGFloat])
			#expect(values[0] + gradient.bounds.width / 2 <= 0)
			#expect(values[1] - gradient.bounds.width / 2 >= label.bounds.width)
			#expect(values[1] > values[0])
			#expect(values[2] == values[1])
			#expect(sweep.calculationMode == .linear)
			#expect(sweep.duration == 2.1)
			#expect(gradient.startPoint.x == 0 && gradient.endPoint.x == 1)
			#expect(overlay.mask?.contents != nil)
			let originalFrame = label.frame
			let originalSize = label.intrinsicContentSize
			var centroids: [Double] = []
			let mask = try render(try #require(overlay.mask))
			for progress in [0.2, 0.5, 0.8]
			{
				gradient.removeAllAnimations()
				gradient.position.x = values[0] + (values[1] - values[0]) * progress
				let pixels = try render(overlay)
				var weight = 0.0
				var weightedX = 0.0
				var pixelsOutsideGlyphs = 0
				for y in 0 ..< pixels.pixelsHigh
				{
					for x in 0 ..< pixels.pixelsWide
					{
						let alpha = try #require(pixels.colorAt(
							x: x,
							y: y
						)).alphaComponent
						let glyphAlpha = try #require(mask.colorAt(
							x: x,
							y: y
						)).alphaComponent
						if glyphAlpha == 0
						{
							if alpha > 0
							{
								pixelsOutsideGlyphs += 1
							}
						}
						weight += alpha
						weightedX += Double(x) * alpha
					}
				}
				#expect(pixelsOutsideGlyphs == 0)
				#expect(weight > 0)
				centroids.append(weightedX / weight)
			}
			#expect(centroids[0] < centroids[1] && centroids[1] < centroids[2])
			#expect(label.frame == originalFrame)
			#expect(label.intrinsicContentSize == originalSize)
		}
	}

	@Test func actionChangesRestartAndCompletionOrRemovalReleasesLayers() throws
	{
		let (label, window) = makeLabel("Thinking")
		label.actionIsActive = true
		let first = try #require(label.highlightLayer)
		label.synchronizeAnimation()
		#expect(label.highlightLayer === first)
		label.stringValue = "Reading"
		#expect(label.highlightLayer !== first)
		#expect(first.superlayer == nil)
		#expect(first.sublayers?.first?.animationKeys()?.isEmpty != false)
		label.actionIsActive = false
		#expect(label.highlightLayer == nil)
		label.actionIsActive = true
		#expect(label.highlightLayer != nil)
		label.presentationIsVisible = false
		#expect(label.highlightLayer == nil)
		label.presentationIsVisible = true
		#expect(label.highlightLayer != nil)
		label.isHidden = true
		#expect(label.highlightLayer == nil)
		label.isHidden = false
		let attached = try #require(label.highlightLayer)
		label.removeFromSuperview()
		#expect(label.highlightLayer == nil)
		#expect(attached.superlayer == nil)
		#expect(attached.sublayers?.first?.animationKeys()?.isEmpty != false)
		window.contentView = nil
	}

	@Test func reduceMotionRetainsStaticTextAndRespondsToChanges()
	{
		let (label, window) = makeLabel("Thinking")
		defer
		{
			window.contentView = nil
		}
		label.actionIsActive = true
		label.shouldReduceMotion =
		{
			true
		}
		NSWorkspace.shared.notificationCenter.post(
			name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
			object: nil
		)
		#expect(label.highlightLayer == nil)
		#expect(label.stringValue == "Thinking")
		label.shouldReduceMotion =
		{
			false
		}
		NSWorkspace.shared.notificationCenter.post(
			name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
			object: nil
		)
		#expect(label.highlightLayer != nil)
	}

	@Test func maskMatchesNativeTextFieldGlyphsIncludingTruncation() throws
	{
		for scale: CGFloat in [1, 2]
		{
			for text in ["Thinking", "Working", "Reading a very long label that is truncated"]
			{
				let (label, window) = makeLabel(text)
				defer
				{
					window.contentView = nil
				}
				label.frame.size.width = 90
				let mask = NSBitmapImageRep(cgImage: try #require(label.glyphMask(scale: scale)))
				#expect(mask.pixelsWide == Int(90 * scale))
				// Independently render an ordinary AppKit field with identical geometry.
				let reference = NSTextField(labelWithString: text)
				reference.font = label.font
				reference.textColor = .white
				reference.lineBreakMode = label.lineBreakMode
				reference.frame = label.bounds
				let native = try #require(NSBitmapImageRep(
					bitmapDataPlanes: nil,
					pixelsWide: mask.pixelsWide,
					pixelsHigh: mask.pixelsHigh,
					bitsPerSample: 8,
					samplesPerPixel: 4,
					hasAlpha: true,
					isPlanar: false,
					colorSpaceName: .deviceRGB,
					bytesPerRow: 0,
					bitsPerPixel: 0
				))
				let context = try #require(NSGraphicsContext(bitmapImageRep: native))
				NSGraphicsContext.saveGraphicsState()
				NSGraphicsContext.current = context
				context.cgContext.scaleBy(
					x: scale,
					y: scale
				)
				reference.draw(reference.bounds)
				NSGraphicsContext.restoreGraphicsState()
				var glyphPixels = 0
				var mismatches = 0
				for y in 0 ..< native.pixelsHigh
				{
					for x in 0 ..< native.pixelsWide
					{
						let expected = try #require(native.colorAt(
							x: x,
							y: y
						)).alphaComponent > 0.3
						let actual = try #require(mask.colorAt(
							x: Int(CGFloat(x) * CGFloat(mask.pixelsWide) /
								CGFloat(native.pixelsWide)),
							y: Int(CGFloat(y) * CGFloat(mask.pixelsHigh) /
								CGFloat(native.pixelsHigh))
						))
						.alphaComponent > 0.3
						if expected
						{
							glyphPixels += 1
						}
						if expected != actual
						{
							mismatches += 1
						}
					}
				}
				#expect(glyphPixels > 0)
				#expect(mismatches == 0)
			}
		}
	}

	private func makeLabel(_ text: String) -> (CurrentActionLabel, NSWindow)
	{
		_ = NSApplication.shared
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 360,
				height: 60
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		let label = CurrentActionLabel(labelWithString: text)
		label.font = .systemFont(ofSize: 12)
		label.textColor = .secondaryLabelColor
		label.lineBreakMode = .byTruncatingTail
		label.frame = NSRect(
			x: 0,
			y: 0,
			width: ceil(label.intrinsicContentSize.width),
			height: 20
		)
		label.shouldReduceMotion =
		{
			false
		}
		window.contentView?.addSubview(label)
		return (label, window)
	}

	private func render(_ layer: CALayer) throws -> NSBitmapImageRep
	{
		let bitmap = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: Int(layer.bounds.width),
			pixelsHigh: Int(layer.bounds.height),
			bitsPerSample: 8,
			samplesPerPixel: 4,
			hasAlpha: true,
			isPlanar: false,
			colorSpaceName: .deviceRGB,
			bytesPerRow: 0,
			bitsPerPixel: 0
		))
		let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
		layer.render(in: context.cgContext)
		return bitmap
	}
}
