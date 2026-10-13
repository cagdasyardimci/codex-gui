import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
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
				AppKitColorTokens.approvalSecondary,
				in: row
			)
			let primary = try resolved(
				AppKitColorTokens.approvalPrimary,
				in: row
			)
			let icon = try resolved(
				AppKitColorTokens.approvalIcon,
				in: row
			)
			if appearance == .darkAqua
			{
				#expect(secondary.alphaComponent == 0.498)
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
