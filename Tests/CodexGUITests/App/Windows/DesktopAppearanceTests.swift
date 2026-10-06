import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct DesktopAppearanceTests
{
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
		button.layerBorderColor = DesktopTheme.border
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
				DesktopTheme.border,
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
				DesktopTheme.canvas,
				in: summary
			)
			try expectColor(
				summary.layer?.borderColor,
				DesktopTheme.border,
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
				DesktopTheme.chrome,
				in: chrome[1]
			)
			try expectColor(
				chrome[2].layer?.borderColor,
				DesktopTheme.border,
				in: chrome[2]
			)
		}
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
