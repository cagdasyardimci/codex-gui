import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct DesktopLayerButtonTests
{
	@Test(.appKitIsolation)
	func inheritedAppearanceRefreshesSemanticTitleAndLayerColorsTogether() throws
	{
		_ = NSApplication.shared
		let window = NSWindow(
			contentRect: NSRect(
				x: -2000,
				y: -2000,
				width: 200,
				height: 100
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
		let button = DesktopLayerButton(frame: NSRect(
			x: 20,
			y: 20,
			width: 140,
			height: 32
		))
		button.wantsLayer = true
		button.layerBackgroundColor = AppKitColorTokens.canvas
		button.layerBorderColor = AppKitColorTokens.border
		button.attributedTitle = NSAttributedString(
			string: "View changes",
			attributes: [.foregroundColor: NSColor.secondaryLabelColor]
		)
		window.contentView?.addSubview(button)
		let cell = button.cell
		button.state = .on

		for name in [NSAppearance.Name.aqua, .darkAqua, .aqua]
		{
			window.appearance = try #require(NSAppearance(named: name))
			window.displayIfNeeded()
			let textColor = try #require(button.attributedTitle.attribute(
				.foregroundColor,
				at: 0,
				effectiveRange: nil
			) as? NSColor)
			#expect(textColor.cgColor.components == AppKitColorResolution.resolvedCGColor(
				.secondaryLabelColor,
				for: button
			).components)
			#expect(button.layer?.backgroundColor?.components
				== AppKitColorResolution.resolvedCGColor(
					AppKitColorTokens.canvas,
					for: button
				).components)
			#expect(button.layer?.borderColor?.components
				== AppKitColorResolution.resolvedCGColor(
					AppKitColorTokens.border,
					for: button
				).components)
			#expect(button.cell === cell)
			#expect(button.state == .on)
			#expect(button.attributedTitle.string == "View changes")
		}
	}
}
