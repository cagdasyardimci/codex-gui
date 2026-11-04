import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct SettingsFormTextFieldTests
{
	@Test func attachedFieldUsesThemeFocusAndValidationBorders() async throws
	{
		try await AppKitTestIsolation.perform
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
			let field = SettingsFormTextField(frame: NSRect(
				x: 20,
				y: 40,
				width: 260,
				height: 36
			))
			window.contentView?.addSubview(field)
			defer
			{
				window.close()
			}
			window.makeKeyAndOrderFront(nil)
			#expect(window.makeFirstResponder(field))
			field.selectText(nil)
			#expect(field.currentEditor() != nil)

			var observed: [(focus: NSColor, error: NSColor)] = []
			for appearanceName in [
				NSAppearance.Name.aqua,
				.darkAqua,
				.aqua,
			]
			{
				window.appearance = NSAppearance(named: appearanceName)
				window.displayIfNeeded()
				field.hasValidationError = false
				let focus = try borderPixel(of: field)
				field.hasValidationError = true
				let error = try borderPixel(of: field)
				var focusRole: NSColor?
				var errorRole: NSColor?
				field.effectiveAppearance.performAsCurrentDrawingAppearance
				{
					focusRole = AppKitColorTokens.settingsFieldFocus.usingColorSpace(.deviceRGB)
					errorRole = AppKitColorTokens.settingsFieldError.usingColorSpace(.deviceRGB)
				}
				let expectedFocus = try #require(focusRole)
				let expectedError = try #require(errorRole)
				#expect(preservesColorOrdering(
					focus,
					of: expectedFocus
				))
				#expect(preservesColorOrdering(
					error,
					of: expectedError
				))
				if maxChannelDelta(
					expectedFocus,
					expectedError
				) > 0.2
				{
					#expect(maxChannelDelta(
						focus,
						error
					) > 0.05)
				}
				observed.append((focus, error))
			}
			let light = observed[0]
			let restoredLight = observed[2]
			// Switching appearances and back must restore the rendered border colors.
			#expect(maxChannelDelta(
				restoredLight.focus,
				light.focus
			) < 0.02)
			#expect(maxChannelDelta(
				restoredLight.error,
				light.error
			) < 0.02)
		}
	}

	@Test(arguments: [SettingsFormTextField.Presentation.outlined, .dialog])
	func editingViewportKeepsPaddedCenteredGeometry(
		_ presentation: SettingsFormTextField.Presentation
	) async throws
	{
		try await AppKitTestIsolation.perform
		{
			_ = NSApplication.shared
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 340,
					height: 120
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
			let field = SettingsFormTextField(
				frame: NSRect(
					x: 20,
					y: 40,
					width: 300,
					height: 36
				),
				presentation: presentation
			)
			window.contentView?.addSubview(field)
			window.makeKeyAndOrderFront(nil)
			#expect(window.makeFirstResponder(field))
			field.selectText(nil)
			let editor = try #require(field.currentEditor() as? NSTextView)
			for width: CGFloat in [300, 180]
			{
				field.frame.size.width = width
				editor.insertText(
					"https://example.invalid/long-path",
					replacementRange: editor.selectedRange()
				)
				let selection = editor.selectedRange()
				field.hasValidationError = true
				field.needsLayout = true
				field.layoutSubtreeIfNeeded()
				let viewport: NSView = (editor.superview as? NSClipView) ?? editor
				let rect = field.convert(
					viewport.bounds,
					from: viewport
				)
				#expect(abs(rect.midY - field.bounds.midY) < 1)
				#expect(abs(rect.minX - 10) < 1)
				#expect(abs(rect.width - (width - 20)) < 1)
				#expect(abs(rect.height - 18) < 1)
				#expect(field.currentEditor() === editor)
				#expect(editor.selectedRange() == selection)
			}
		}
	}

	private func borderPixel(of field: SettingsFormTextField) throws -> NSColor
	{
		let bitmap = try #require(field.bitmapImageRepForCachingDisplay(in: field.bounds))
		field.cacheDisplay(
			in: field.bounds,
			to: bitmap
		)
		let scale = CGFloat(bitmap.pixelsWide) / field.bounds.width
		let x = Int(field.bounds.midX * scale)
		return try #require(bitmap.colorAt(
			x: x,
			y: 0
		)?.usingColorSpace(.deviceRGB))
	}

	private func preservesColorOrdering(
		_ pixel: NSColor,
		of role: NSColor
	) -> Bool
	{
		let expected = [role.redComponent, role.greenComponent, role.blueComponent]
		let actual = [pixel.redComponent, pixel.greenComponent, pixel.blueComponent]
		for first in 0 ..< 3
		{
			for second in (first + 1) ..< 3
			{
				let expectedDifference = expected[first] - expected[second]
				if abs(expectedDifference) > 0.1
				{
					let actualDifference = actual[first] - actual[second]
					if actualDifference * expectedDifference <= 0.001
					{
						return false
					}
				}
			}
		}
		return true
	}

	private func maxChannelDelta(
		_ first: NSColor,
		_ second: NSColor
	) -> CGFloat
	{
		max(
			abs(first.redComponent - second.redComponent),
			max(
				abs(first.greenComponent - second.greenComponent),
				abs(first.blueComponent - second.blueComponent)
			)
		)
	}
}
