import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct ContextPanelAppearanceTests
{
	@Test func sourcesHeaderUpdatesWithoutReplacingContentOrFocus() throws
	{
		_ = NSApplication.shared
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 320,
				height: 180
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.appearance = NSAppearance(named: .aqua)
		defer
		{
			window.close()
		}
		let shell = ContextPanelShell()
		let feature = NSViewController()
		let focus = NSTextView(frame: NSRect(
			x: 0,
			y: 0,
			width: 280,
			height: 80
		))
		feature.view = focus
		shell.register(
			feature,
			for: .sources
		)
		#expect(shell.open(.sources))
		window.contentViewController = shell
		#expect(window.makeFirstResponder(focus))
		let stack = try #require(shell.view.subviews.first as? NSStackView)
		let header = try #require(stack.arrangedSubviews.first as? NSStackView)
		let close = try #require(header.arrangedSubviews.last as? NSButton)
		let label = close.accessibilityLabel()
		for appearance: NSAppearance.Name in [.aqua, .darkAqua, .aqua, .darkAqua]
		{
			window.appearance = NSAppearance(named: appearance)
			shell.view.layoutSubtreeIfNeeded()
			#expect(header.appearance == nil)
			#expect(header.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == appearance)
			try expectColor(
				header.layer?.backgroundColor,
				.controlBackgroundColor,
				in: header
			)
			#expect(!header.isHidden)
			#expect(!close.isHidden)
			#expect(close.accessibilityLabel() == label)
			#expect(shell.destination == .sources)
			#expect(shell.children.first === feature)
			#expect(feature.view === focus)
			#expect(window.firstResponder === focus)
		}
	}

	private func expectColor(
		_ actualCGColor: CGColor?,
		_ semantic: NSColor,
		in view: NSView,
		alpha: CGFloat = 1
	) throws
	{
		let actual = try #require(actualCGColor
			.flatMap
			{
				NSColor(cgColor: $0)?.usingColorSpace(.deviceRGB)
			})
		var expected: NSColor?
		view.effectiveAppearance
			.performAsCurrentDrawingAppearance
			{
				expected = semantic.usingColorSpace(.deviceRGB)
			}
		let color = try #require(expected)
		#expect(abs(actual.redComponent - color.redComponent) < 0.01)
		#expect(abs(actual.greenComponent - color.greenComponent) < 0.01)
		#expect(abs(actual.blueComponent - color.blueComponent) < 0.01)
		#expect(abs(actual.alphaComponent - alpha) < 0.01)
	}
}
