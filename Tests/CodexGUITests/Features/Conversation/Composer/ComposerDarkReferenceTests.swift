import AppKit
import Testing

@testable import CodexGUI

@Suite(
	.serialized
) @MainActor
struct ComposerDarkReferenceTests
{
	@Test func retainedInsetEdgeStaysInsideComposerAcrossAppearanceAndResize() throws
	{
		_ = NSApplication.shared
		let surface = DesktopSurface(
			AppKitColorTokens.composer,
			cornerRadius: ShapeTokens.Composer.cornerRadius,
			shadows: ShadowTokens.composer
		)
		let window = makeWindow(content: surface)
		defer
		{
			window.close()
		}
		window.layoutIfNeeded()
		surface.layoutSubtreeIfNeeded()
		let layers = try #require(surface.layer?.sublayers)
		let inset = try #require(layers.first
		{
			$0.shadowRadius == 0.5
		})
		let outsideEdge = try #require(layers.first
		{
			$0.shadowRadius == 0
		})
		for appearance: NSAppearance.Name in [.darkAqua, .aqua, .darkAqua, .aqua]
		{
			window.appearance = NSAppearance(named: appearance)
			window.setContentSize(NSSize(
				width: appearance == .darkAqua ? 300 : 240,
				height: 98
			))
			surface.layoutSubtreeIfNeeded()
			let innerColor = try #require(inset.shadowColor.flatMap
			{
				NSColor(cgColor: $0)
			})
			let outerColor = try #require(outsideEdge.shadowColor.flatMap
			{
				NSColor(cgColor: $0)
			})
			#expect(abs(innerColor.alphaComponent - (appearance == .darkAqua ? 0.2 : 0)) < 0.0001)
			#expect(abs(outerColor.alphaComponent - (appearance == .darkAqua ? 0 : 0.04)) < 0.0001)
			let mask = try #require(inset.mask as? CAShapeLayer)
			#expect(mask.frame == surface.bounds)
			#expect(mask.path?.boundingBox == surface.bounds)
			let path = try #require(inset.shadowPath)
			#expect(!path.contains(CGPoint(
				x: surface.bounds.midX,
				y: surface.bounds.midY
			)))
			#expect(path.contains(CGPoint(
				x: -1,
				y: surface.bounds.midY
			)))
			#expect(surface.layer?.sublayers?.contains(where:
				{
					$0 === inset
				}) == true)
		}
	}

	@Test func approvalHoverOpacityAndPaletteFollowRetainedAppearance() throws
	{
		_ = NSApplication.shared
		let controller = ApprovalPolicyPopoverView()
		let window = makeWindow(content: controller.view)
		window.setContentSize(controller.preferredContentSize)
		defer
		{
			window.close()
		}
		controller.render(mode: .askForApproval)
		window.layoutIfNeeded()
		let stack = try #require(controller.view.subviews.first?.subviews.first as? NSStackView)
		let row = try #require(stack.arrangedSubviews.compactMap
		{
			$0 as? NSButton
		}.first)
		let images = row.subviews.compactMap
		{
			$0 as? NSImageView
		}
		let labels = row.subviews.compactMap
		{
			$0 as? NSTextField
		}
		try #require(labels.count == 2)
		try #require(images.count == 2)
		let event = try #require(NSEvent.mouseEvent(
			with: .mouseMoved,
			location: .zero,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: window.windowNumber,
			context: nil,
			eventNumber: 0,
			clickCount: 0,
			pressure: 0
		))
		row.mouseEntered(with: event)
		for appearance: NSAppearance.Name in [.darkAqua, .aqua, .darkAqua, .aqua]
		{
			window.appearance = NSAppearance(named: appearance)
			#expect(images.allSatisfy
			{
				$0.alphaValue == (appearance == .darkAqua ? 1 : 0.75)
			})
			let secondary = try resolved(
				#require(labels[1].textColor),
				in: labels[1]
			)
			let primary = try resolved(
				#require(labels[0].textColor),
				in: labels[0]
			)
			let icon = try resolved(
				#require(images[0].contentTintColor),
				in: images[0]
			)
			let check = try resolved(
				#require(images[1].contentTintColor),
				in: images[1]
			)
			if appearance == .darkAqua
			{
				#expect(secondary.alphaComponent == 0.498)
				#expect(secondary.redComponent == 1)
				#expect(primary.redComponent == 1)
				#expect(icon.redComponent == 1)
			}
			else
			{
				#expect(abs(secondary.redComponent - 0.57) < 0.0001)
				#expect(secondary.alphaComponent == 1)
				#expect(abs(primary.redComponent - 0.13) < 0.0001)
				#expect(abs(icon.redComponent - 0.33) < 0.0001)
			}
			for color in [primary, secondary, icon, check]
			{
				#expect(abs(color.greenComponent - color.redComponent) < 0.0001)
				#expect(abs(color.blueComponent - color.redComponent) < 0.0001)
			}
			#expect(primary.alphaComponent == 1)
			#expect(icon.alphaComponent == 1)
			#expect(check == primary)
			#expect(row.accessibilityValue() as? String == "Selected")
		}
		row.mouseExited(with: event)
		#expect(images.allSatisfy
		{
			$0.alphaValue == 0.75
		})
	}

	@Test func effortActionCanvasesAndControlsUseMeasuredGeometry() throws
	{
		_ = NSApplication.shared
		let picker = ModelEffortPopoverView()
		let window = makeWindow(content: picker.view)
		window.setContentSize(picker.preferredContentSize)
		defer
		{
			window.close()
		}
		window.layoutIfNeeded()
		picker.view.layoutSubtreeIfNeeded()
		let actions = picker.view.subviews.compactMap
		{
			$0 as? NSButton
		}
		.filter
		{
			$0.imagePosition == .imageOnly
		}
		#expect(actions.count == 2)
		for action in actions
		{
			#expect(action.bounds.size == NSSize(
				width: 32,
				height: 32
			))
			#expect(action.image?.size == NSSize(
				width: 16,
				height: 16
			))
		}
		#expect(actions.map(\.frame.minX).sorted() == [4, 218])
		let model = try #require(picker.view.subviews.compactMap
		{
			$0 as? NSButton
		}
		.first
		{
			$0.accessibilityLabel() == "Choose Codex model"
		})
		#expect(model.image?.size == NSSize(
			width: 12,
			height: 12
		))
		#expect(picker.preferredContentSize == NSSize(
			width: 254,
			height: 96
		))
		window.appearance = NSAppearance(named: .darkAqua)
		let tick = try resolved(
			AppKitColorTokens.effortTick,
			in: picker.view
		)
		let edge = try resolved(
			AppKitColorTokens.effortTrackEdge,
			in: picker.view
		)
		#expect(tick.alphaComponent == 0.24902)
		#expect(edge.alphaComponent == 0.082)
	}

	@Test func renderedEffortTicksAndEdgeFollowRetainedAppearance() throws
	{
		_ = NSApplication.shared
		let picker = ModelEffortPopoverView()
		let window = makeWindow(content: picker.view)
		defer
		{
			window.close()
		}
		let model = try #require(ModelOption(json: [
			"model": "palette-model",
			"displayName": "Palette model",
			"supportedReasoningEfforts": [
				["reasoningEffort": "low"],
				["reasoningEffort": "medium"],
				["reasoningEffort": "high"],
			],
		]))
		picker.render(
			models: [model],
			selectedModelID: model.id,
			selectedEffort: "low",
			fastMode: false
		)
		window.setContentSize(picker.preferredContentSize)
		window.layoutIfNeeded()
		picker.view.layoutSubtreeIfNeeded()
		let slider = try #require(picker.view.subviews.compactMap
		{
			$0 as? NSSlider
		}.first)
		#expect(slider.isEnabled)
		#expect(slider.numberOfTickMarks == 3)
		#expect(slider.doubleValue == 0)
		for appearance: NSAppearance.Name in [.darkAqua, .aqua, .darkAqua, .aqua]
		{
			window.appearance = NSAppearance(named: appearance)
			#expect(slider.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == appearance)
			let bitmap = try renderedSlider(slider)
			let pixels = try #require(bitmap.data?.assumingMemoryBound(to: UInt8.self))
			let dark = appearance == .darkAqua
			// Independent palette values composited over the 10% track on transparency:
			// alpha = foreground + track * (1 - foreground).
			let expectedRGB: [CGFloat] = dark ? [1, 1, 1] : [26 / 255, 28 / 255, 31 / 255]
			let samples: [(NSPoint, CGFloat)] = [
				// The 28-point thumb centers the final unfilled tick 14 points from the end.
				(
					NSPoint(
						x: slider.bounds.maxX - 14,
						y: slider.bounds.midY
					),
					dark ? 0.324118 : 0.3223531
				),
				// Middle of the 0.5-point edge, away from ticks and thumb.
				(
					NSPoint(
						x: slider.bounds.midX + 20,
						y: slider.bounds.midY - 11.75
					),
					dark ? 0.1738 : 0.172
				),
			]
			for (point, alpha) in samples
			{
				let offset = Int(point.y * 8) * bitmap.bytesPerRow + Int(point.x * 8) * 4
				let actualRGBA = (0 ..< 4).map
				{
					CGFloat(pixels[offset + $0]) / 255
				}
				let expectedRGBA = expectedRGB.map
				{
					$0 * alpha
				} + [alpha]
				// Compare the explicit premultiplied sRGB bytes without NSColor profile conversion.
				for (actual, expected) in zip(
					actualRGBA,
					expectedRGBA
				)
				{
					#expect(abs(actual - expected) < 1.5 / 255)
				}
			}
		}
	}

	private func renderedSlider(_ slider: NSSlider) throws -> CGContext
	{
		let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
		let context = try #require(CGContext(
			data: nil,
			width: Int(slider.bounds.width * 8),
			height: Int(slider.bounds.height * 8),
			bitsPerComponent: 8,
			bytesPerRow: 0,
			space: colorSpace,
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
				| CGBitmapInfo.byteOrder32Big.rawValue
		))
		NSGraphicsContext.saveGraphicsState()
		defer
		{
			NSGraphicsContext.restoreGraphicsState()
		}
		NSGraphicsContext.current = NSGraphicsContext(
			cgContext: context,
			flipped: slider.isFlipped
		)
		context.scaleBy(
			x: 8,
			y: 8
		)
		// Exercise the configured control's real drawing, with an isolated transparent backdrop.
		slider.effectiveAppearance.performAsCurrentDrawingAppearance
		{
			slider.draw(slider.bounds)
		}
		return context
	}

	private func resolved(
		_ color: NSColor,
		in view: NSView
	) throws -> NSColor
	{
		try #require(NSColor(cgColor: AppKitColorResolution.resolvedCGColor(
			color,
			for: view
		))?
			.usingColorSpace(.sRGB))
	}

	private func makeWindow(content: NSView) -> NSWindow
	{
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 254,
				height: 98
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentView = content
		return window
	}
}
