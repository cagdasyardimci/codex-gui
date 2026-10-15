import AppKit
import Testing

@testable import CodexGUI

@Suite(
	.serialized
) @MainActor
struct DesktopAppearanceTests
{
	@Test func retainedSurfaceShadowsFollowAppearanceAndResizeWithoutReplacingLayers() throws
	{
		_ = NSApplication.shared
		let window = makeWindow()
		defer
		{
			window.close()
		}
		let surface = DesktopSurface(
			AppKitColorTokens.composer,
			cornerRadius: 22,
			shadows: ShadowTokens.composer
		)
		surface.frame = NSRect(
			x: 0,
			y: 0,
			width: 220,
			height: 100
		)
		window.contentView?.addSubview(surface)
		let editor = NSTextView(frame: NSRect(
			x: 12,
			y: 12,
			width: 180,
			height: 60
		))
		editor.string = "Retained draft"
		surface.addSubview(editor)
		#expect(window.makeFirstResponder(editor))
		editor.setSelectedRange(NSRange(
			location: 2,
			length: 4
		))
		let layers = try #require(surface.layer?.sublayers)
		try #require(layers.count >= ShadowTokens.composer.count)
		let shadows = Array(layers.prefix(ShadowTokens.composer.count))
		for name: NSAppearance.Name in [.aqua, .darkAqua, .aqua, .darkAqua]
		{
			window.appearance = NSAppearance(named: name)
			surface.setFrameSize(NSSize(
				width: name == .aqua ? 240 : 280,
				height: 100
			))
			surface.layoutSubtreeIfNeeded()
			let broadShadow = try #require(shadows.first
			{
				$0.shadowRadius == 40
			})
			let color = try #require(broadShadow.shadowColor.flatMap
			{
				NSColor(cgColor: $0)
			})
			#expect(abs(color.alphaComponent - (name == .aqua ? 0.024 : 0)) < 0.001)
			#expect(broadShadow.frame == surface.bounds)
			#expect(broadShadow.shadowPath?.boundingBox.width == surface.bounds.width + 16)
			#expect(window.firstResponder === editor)
			#expect(editor.string == "Retained draft")
			#expect(editor.selectedRange() == NSRange(
				location: 2,
				length: 4
			))
			#expect(shadows.allSatisfy
			{
				shadow in
				surface.layer?.sublayers?.contains
				{
					$0 === shadow
				} == true
			})
		}
	}

	@Test func layerButtonFollowsItsWindowAndRetainsInteractionState() throws
	{
		_ = NSApplication.shared
		let window = makeWindow()
		defer
		{
			window.close()
		}
		let button = DesktopLayerButton(
			title: "Action",
			target: nil,
			action: nil
		)
		button.frame = NSRect(
			x: 0,
			y: 0,
			width: 120,
			height: 30
		)
		button.wantsLayer = true
		button.layerBackgroundColor = .labelColor
		button.layerBackgroundAlpha = 0.18
		button.layerBorderColor = AppKitColorTokens.border
		button.state = .on
		window.contentView?.addSubview(button)
		#expect(window.makeFirstResponder(button))
		for name: NSAppearance.Name in [.aqua, .darkAqua, .aqua, .darkAqua, .aqua]
		{
			window.appearance = NSAppearance(named: name)
			try expectColor(
				button.layer?.backgroundColor,
				.labelColor,
				in: button,
				alpha: 0.18
			)
			try expectColor(
				button.layer?.borderColor,
				AppKitColorTokens.border,
				in: button
			)
			#expect(button.state == .on)
			#expect(button.title == "Action")
			#expect(window.firstResponder === button)
		}
		button.layerBackgroundColor = nil
		button.layerBorderColor = nil
		#expect(button.layer?.backgroundColor == nil)
		#expect(button.layer?.borderColor == nil)
	}

	@Test func bindingTracksOwnerOverridesAndStopsAfterInvalidation() throws
	{
		_ = NSApplication.shared
		let window = makeWindow()
		let source = NSView(frame: window.contentView!.bounds)
		window.contentView?.addSubview(source)
		let panel = NSPanel(
			contentRect: source.bounds,
			styleMask: [.borderless, .nonactivatingPanel],
			backing: .buffered,
			defer: false
		)
		panel.isReleasedWhenClosed = false
		defer
		{
			panel.close()
			window.close()
		}
		let binding = DesktopPanelAppearanceBinding(
			panel: panel,
			source: source
		)
		for name: NSAppearance.Name in [.aqua, .darkAqua, .aqua, .darkAqua]
		{
			window.appearance = NSAppearance(named: name)
			#expect(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == name)
		}
		source.appearance = NSAppearance(named: .aqua)
		#expect(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua)
		binding.invalidate()
		source.appearance = NSAppearance(named: .darkAqua)
		#expect(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua)
	}

	@Test func existingLayerOwnersResolveInheritedAppearance() throws
	{
		_ = NSApplication.shared
		let window = makeWindow()
		defer
		{
			window.close()
		}
		let controller = WindowChromeViewController(
			split: NSSplitViewController(),
			accountButton: NSButton()
		)
		window.contentViewController = controller
		let summary = TurnChangeSummaryButton()
		let ring = TaskProgressRingView(frame: NSRect(
			x: 0,
			y: 0,
			width: 16,
			height: 16
		))
		controller.view.addSubview(summary)
		controller.view.addSubview(ring)
		for name: NSAppearance.Name in [.aqua, .darkAqua, .aqua, .darkAqua]
		{
			window.appearance = NSAppearance(named: name)
			controller.view.layoutSubtreeIfNeeded()
			try expectColor(
				summary.layer?.backgroundColor,
				AppKitColorTokens.canvas,
				in: summary
			)
			try expectColor(
				summary.layer?.borderColor,
				AppKitColorTokens.border,
				in: summary
			)
			let shape = try #require(ring.layer?.sublayers?.first as? CAShapeLayer)
			try expectColor(
				shape.strokeColor,
				.secondaryLabelColor,
				in: ring
			)
			let chrome = Array(controller.view.subviews.prefix(3))
			try #require(chrome.count == 3)
			try expectColor(
				chrome[1].layer?.backgroundColor,
				AppKitColorTokens.chrome,
				in: chrome[1]
			)
			try expectColor(
				chrome[2].layer?.borderColor,
				AppKitColorTokens.border,
				in: chrome[2]
			)
		}
	}

	@Test func chromeAndRunningRingUseOwnerAppearanceDespiteOppositeDrawingAppearance() throws
	{
		_ = NSApplication.shared
		let window = makeWindow()
		window.appearance = NSAppearance(named: .aqua)
		defer
		{
			window.close()
		}
		let dark = try #require(NSAppearance(named: .darkAqua))
		var controller: WindowChromeViewController!
		var ring: TaskProgressRingView!
		dark.performAsCurrentDrawingAppearance
		{
			controller = WindowChromeViewController(
				split: NSSplitViewController(),
				accountButton: NSButton()
			)
			window.contentViewController = controller
			ring = TaskProgressRingView(frame: NSRect(
				x: 0,
				y: 0,
				width: 16,
				height: 16
			))
			controller.view.addSubview(ring)
			ring.setRunning(true)
			controller.view.layoutSubtreeIfNeeded()
		}
		let shadow = try #require(controller.view.subviews.dropFirst().first)
		let panel = try #require(controller.view.subviews.dropFirst(2).first)
		let shape = try #require(ring.layer?.sublayers?.first as? CAShapeLayer)
		let ringFrame = ring.frame
		for name: NSAppearance.Name in [.aqua, .darkAqua, .aqua, .darkAqua, .aqua]
		{
			let ambient = try #require(NSAppearance(named: name == .aqua ? .darkAqua : .aqua))
			ambient.performAsCurrentDrawingAppearance
			{
				window.appearance = NSAppearance(named: name)
				controller.view.layoutSubtreeIfNeeded()
			}
			try expectColor(
				shadow.layer?.backgroundColor,
				AppKitColorTokens.chrome,
				in: shadow
			)
			try expectColor(
				panel.layer?.borderColor,
				AppKitColorTokens.border,
				in: panel
			)
			try expectColor(
				shape.strokeColor,
				.secondaryLabelColor,
				in: ring
			)
			#expect(shadow.layer?.shadowOpacity == (name == .darkAqua ? 0 : 0.08))
			#expect(panel.layer?.borderWidth == 0.5)
			#expect(ring.frame == ringFrame)
			#expect(ring.isRunning)
			#expect(!ring.isHidden)
			#expect(shape.animation(forKey: "taskRotation") != nil)
		}
		controller.setGitReviewFocused(true)
		controller.view.layoutSubtreeIfNeeded()
		window.appearance = NSAppearance(named: .darkAqua)
		controller.view.layoutSubtreeIfNeeded()
		#expect(shadow.isHidden)
		#expect(panel.layer?.borderWidth == 0)
		#expect(panel.layer?.cornerRadius == 0)
		ring.setRunning(false)
		window.appearance = NSAppearance(named: .aqua)
		controller.view.layoutSubtreeIfNeeded()
		#expect(ring.isHidden)
		#expect(shape.animation(forKey: "taskRotation") == nil)
	}

	@Test func turnChangeSummaryRefreshesColorsWithoutRerendering() throws
	{
		_ = NSApplication.shared
		let window = makeWindow()
		defer
		{
			window.close()
		}
		let button = TurnChangeSummaryButton()
		window.contentView?.addSubview(button)
		button.render(ConversationTurnChangeSummary(
			ConversationTurnChangeSummaryTestFixture.makeSnapshot()
		))
		let title = button.attributedTitle.string
		let size = button.intrinsicContentSize
		let accessibilityLabel = button.accessibilityLabel()
		#expect(window.makeFirstResponder(button))
		for name: NSAppearance.Name in [.aqua, .darkAqua, .aqua, .darkAqua, .aqua]
		{
			let ambient = try #require(NSAppearance(named: name == .aqua ? .darkAqua : .aqua))
			ambient.performAsCurrentDrawingAppearance
			{
				window.appearance = NSAppearance(named: name)
			}
			try expectColor(
				button.layer?.backgroundColor,
				AppKitColorTokens.canvas,
				in: button
			)
			try expectColor(
				button.layer?.borderColor,
				AppKitColorTokens.border,
				in: button
			)
			for (text, semantic) in [
				("2 files changed", NSColor.secondaryLabelColor),
				("+3", NSColor.systemGreen),
				("-1", NSColor.systemRed),
			]
			{
				let index = (title as NSString).range(of: text).location
				let color = try #require(button.attributedTitle.attribute(
					.foregroundColor,
					at: index,
					effectiveRange: nil
				) as? NSColor)
				try expectColor(
					color.cgColor,
					semantic,
					in: button
				)
			}
			#expect(button.attributedTitle.string == title)
			#expect(button.intrinsicContentSize == size)
			#expect(button.accessibilityLabel() == accessibilityLabel)
			#expect(button.toolTip == GitReportedTurnComparison.coverageMessage)
			#expect(!button.isHidden)
			#expect(window.firstResponder === button)
		}
		button.render(nil)
		window.appearance = NSAppearance(named: .darkAqua)
		#expect(button.isHidden)
	}

	private func makeWindow() -> NSWindow
	{
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 360,
				height: 240
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		return window
	}

	private func expectColor(
		_ actual: CGColor?,
		_ semantic: NSColor,
		in view: NSView,
		alpha: CGFloat? = nil
	) throws
	{
		let color = try #require(actual.flatMap
		{
			NSColor(cgColor: $0)
		}?
		.usingColorSpace(.deviceRGB))
		var expected: NSColor?
		view.effectiveAppearance.performAsCurrentDrawingAppearance
		{
			expected = semantic.usingColorSpace(.deviceRGB)
		}
		let resolved = try #require(expected)
		#expect(abs(color.redComponent - resolved.redComponent) < 0.01)
		#expect(abs(color.greenComponent - resolved.greenComponent) < 0.01)
		#expect(abs(color.blueComponent - resolved.blueComponent) < 0.01)
		#expect(abs(color.alphaComponent - (alpha ?? resolved.alphaComponent)) < 0.01)
	}
}
