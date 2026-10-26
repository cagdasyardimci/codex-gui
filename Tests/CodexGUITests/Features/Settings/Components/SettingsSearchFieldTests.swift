import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct SettingsSearchFieldTests
{
	@Test(
		.appKitIsolation,
		arguments: [
			DesktopSearchField.Presentation.settingsFilled,
			.settingsOutlined,
			.settingsCatalog,
		]
	)
	func activeSearchCaretTracksWindowAppearance(
		presentation: DesktopSearchField.Presentation
	) throws
	{
		_ = NSApplication.shared
		let window = NSWindow(
			contentRect: NSRect(
				x: 100,
				y: 100,
				width: 300,
				height: 120
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		let field = DesktopSearchField(
			frame: NSRect(
				x: 20,
				y: 40,
				width: 260,
				height: 36
			),
			presentation: presentation
		)
		field.stringValue = "draft"
		window.contentView?.addSubview(field)
		defer
		{
			window.close()
		}
		window.makeKeyAndOrderFront(nil)
		#expect(window.makeFirstResponder(field))
		field.selectText(nil)
		let editor = try #require(field.currentEditor() as? NSTextView)
		editor.setSelectedRange(NSRange(
			location: 1,
			length: 2
		))

		for (appearance, expectedColor) in [
			(NSAppearance.Name.aqua, 0x0D0D0D),
			(.darkAqua, 0xFFFFFF),
			(.aqua, 0x0D0D0D),
		]
		{
			window.appearance = NSAppearance(named: appearance)
			window.displayIfNeeded()
			#expect(field.currentEditor() === editor)
			#expect(editor.selectedRange() == NSRange(
				location: 1,
				length: 2
			))
			#expect(field.stringValue == "draft")
			#expect(try rgb(
				editor.insertionPointColor,
				appearance: window.effectiveAppearance
			) == expectedColor)
		}
	}

	private func rgb(
		_ color: NSColor,
		appearance: NSAppearance
	) throws -> Int
	{
		var resolved: NSColor?
		appearance.performAsCurrentDrawingAppearance
		{
			resolved = color.usingColorSpace(.deviceRGB)
		}
		let color = try #require(resolved)
		return (Int((color.redComponent * 255).rounded()) << 16)
			| (Int((color.greenComponent * 255).rounded()) << 8)
			| Int((color.blueComponent * 255).rounded())
	}
}
