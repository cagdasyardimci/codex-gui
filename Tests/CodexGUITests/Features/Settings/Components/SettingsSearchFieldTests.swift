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

		for (appearance, mode) in [
			(NSAppearance.Name.aqua, ColorAppearance.light),
			(.darkAqua, .dark),
			(.aqua, .light),
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
			let profile = ColorPreferences().configuration.profile(for: mode)
			let expectedColor = ColorPalette(
				configuration: profile,
				mode: mode
			).foreground
			#expect(try rgb(
				editor.insertionPointColor,
				appearance: window.effectiveAppearance
			) == rgb(
				expectedColor,
				appearance: window.effectiveAppearance
			))
		}
	}

	@Test(.appKitIsolation)
	func overlaySearchStylesAndRestoresSharedFieldEditor() throws
	{
		_ = NSApplication.shared
		let window = NSWindow(
			contentRect: NSRect(
				x: 100,
				y: 100,
				width: 320,
				height: 140
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		let previous = NSTextField(frame: NSRect(
			x: 20,
			y: 20,
			width: 260,
			height: 28
		))
		let search = DesktopSearchField(
			frame: NSRect(
				x: 20,
				y: 70,
				width: 260,
				height: 32
			),
			presentation: .viewerOverlay
		)
		search.stringValue = "font"
		window.contentView?.addSubview(previous)
		window.contentView?.addSubview(search)
		defer
		{
			window.close()
		}
		window.makeKeyAndOrderFront(nil)
		#expect(window.makeFirstResponder(previous))
		let shared = try #require(previous.currentEditor() as? NSTextView)
		let originalSelection = shared.selectedTextAttributes
		let originalCaret = shared.insertionPointColor
		#expect(window.makeFirstResponder(search))
		let editor = try #require(search.currentEditor() as? NSTextView)
		#expect(editor === shared)
		editor.setSelectedRange(NSRange(
			location: 0,
			length: 4
		))
		let selectedBackground = try #require(editor
			.selectedTextAttributes[.backgroundColor] as? NSColor)
		let expectedBackground = AppKitColorTokens.paletteColor
		{
			$0.selectionBackground
		}
		let appearance = window.effectiveAppearance
		#expect(try rgb(
			selectedBackground,
			appearance: appearance
		) == rgb(
			expectedBackground,
			appearance: appearance
		))
		let selectedColor = try #require(selectedBackground.usingColorSpace(.sRGB))
		let expectedColor = try #require(expectedBackground.usingColorSpace(.sRGB))
		#expect(abs(selectedColor.alphaComponent - expectedColor.alphaComponent) < 0.001)
		NotificationCenter.default.post(
			name: ColorPreferences.didChange,
			object: nil
		)
		#expect(search.stringValue == "font")
		#expect(editor.selectedRange() == NSRange(
			location: 0,
			length: 4
		))
		#expect(window.makeFirstResponder(nil))
		#expect(shared.insertionPointColor == originalCaret)
		#expect(NSDictionary(dictionary: shared.selectedTextAttributes)
			.isEqual(to: originalSelection))
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
