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
