import AppKit
import Testing

@testable import CodexGUI

@Suite(
	.serialized
) @MainActor
struct ToolsTabAppearanceTests
{
	@Test func mutualComponentsKeepMeasuredFontsAndActionWithoutGlobe() throws
	{
		_ = NSApplication.shared
		let controller = ToolsTabViewController()
		controller.openNewTab()
		let header = controller.tabBarView
		let selected = try #require(button(
			"New tab 1",
			in: header
		))
		#expect(selected.image == nil)
		#expect(selected.font?.fontName
			== ".SFNS-Regular_wdth_opsz110000_GRAD_wght1AE0000")
		let changes = try #require(button(
			"Changes",
			in: controller.view
		))
		#expect(changes.font?.fontName == ".SFNS-Regular_wdth_opsz110000_GRAD_wght")
		#expect(changes.keyEquivalent == "g")
		#expect(changes.keyEquivalentModifierMask == [.control, .shift])
		var activations = 0
		controller.onOpenChanges =
		{
			activations += 1
		}
		let event = try #require(NSEvent.keyEvent(
			with: .keyDown,
			location: .zero,
			modifierFlags: [.control, .shift],
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			characters: "G",
			charactersIgnoringModifiers: "g",
			isARepeat: false,
			keyCode: 5
		))
		#expect(changes.performKeyEquivalent(with: event))
		#expect(activations == 1)
	}

	@Test func retainedTabSurfacesPaintSelectionAndHoverInBothAppearances() throws
	{
		_ = NSApplication.shared
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 260,
				height: 80
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		defer
		{
			window.close()
		}
		let selected = ToolsTabSurface(isSelected: true)
		let hovered = ToolsTabSurface(isSelected: false)
		let event = try #require(NSEvent.otherEvent(
			with: .applicationDefined,
			location: .zero,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: window.windowNumber,
			context: nil,
			subtype: 0,
			data1: 0,
			data2: 0
		))
		for tab in [selected, hovered]
		{
			tab.frame = NSRect(
				x: 0,
				y: 0,
				width: 238,
				height: 32
			)
			window.contentView?.addSubview(tab)
		}
		hovered.mouseEntered(with: event)
		for name: NSAppearance.Name in [.aqua, .darkAqua, .aqua, .darkAqua]
		{
			window.appearance = NSAppearance(named: name)
			window.layoutIfNeeded()
			let dark = name == .darkAqua
			for (tab, expected) in [(selected, dark ? 53 : 255), (hovered, dark ? 53 : 234)]
			{
				let bitmap = try paint(
					tab,
					dark: dark
				)
				let center = try #require(bitmap.colorAt(
					x: 119,
					y: 16
				)?.usingColorSpace(.sRGB))
				#expect(abs(center.redComponent * 255 - CGFloat(expected)) <= 1)
				let corner = try #require(bitmap.colorAt(
					x: 0,
					y: 0
				)?.usingColorSpace(.sRGB))
				#expect(abs(corner.redComponent * 255 - CGFloat(dark ? 36 : 246)) <= 1)
				#expect(tab.bounds.size == NSSize(
					width: 238,
					height: 32
				))
			}
			hovered.mouseExited(with: event)
			let rest = try paint(
				hovered,
				dark: dark
			)
			let color = try #require(rest.colorAt(
				x: 119,
				y: 16
			)?.usingColorSpace(.sRGB))
			#expect(abs(color.redComponent * 255 - CGFloat(dark ? 36 : 246)) <= 1)
			hovered.mouseEntered(with: event)
			let shadow = try #require(selected.layer?.sublayers?.first)
			#expect(shadow.shadowRadius == 1)
			#expect(shadow.shadowPath?.boundingBox.width == 236)
		}
	}

	@Test func retainedToolsTileReplacesRestingFillOnHover() throws
	{
		_ = NSApplication.shared
		let controller = ToolsTabViewController()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 320,
				height: 200
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		let host = try #require(window.contentView)
		controller.view.frame = host.bounds
		host.addSubview(controller.view)
		defer
		{
			window.close()
		}
		func findButton(_ view: NSView) -> NSButton?
		{
			if let button = view as? NSButton, button.title == "Changes"
			{
				return button
			}
			return view.subviews.compactMap
			{
				findButton($0)
			}.first
		}
		let button = try #require(findButton(controller.view))
		let event = try #require(NSEvent.otherEvent(
			with: .applicationDefined,
			location: .zero,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: window.windowNumber,
			context: nil,
			subtype: 0,
			data1: 0,
			data2: 0
		))
		for name: NSAppearance.Name in [.aqua, .darkAqua, .aqua]
		{
			window.appearance = NSAppearance(named: name)
			window.layoutIfNeeded()
			#expect(button.bounds.height == 40)
			#expect(button.image?.size == NSSize(
				width: 16,
				height: 16
			))
			#expect(button.action != nil)
			let dark = name == .darkAqua
			for (hover, expected) in [(false, dark ? 31 : 255), (true, dark ? 42 : 238)]
			{
				if hover
				{
					button.mouseEntered(with: event)
				}
				else
				{
					button.mouseExited(with: event)
				}
				let bitmap = try paint(
					button,
					dark: dark,
					tools: true
				)
				let pixel = try #require(bitmap.colorAt(
					x: Int(button.bounds.width / 2),
					y: 20
				)?.usingColorSpace(.sRGB))
				#expect(abs(pixel.redComponent * 255 - CGFloat(expected)) <= 1)
			}
			button.mouseExited(with: event)
			let resting = try paint(
				button,
				dark: dark,
				tools: true,
				scale: 2
			)
			let cell = try #require(button.cell)
			let iconRange = paintedRedRange(
				resting,
				in: cell.imageRect(forBounds: button.bounds)
			)
			let titleRange = paintedRedRange(
				resting,
				in: cell.titleRect(forBounds: button.bounds)
			)
			#expect(dark ? abs(iconRange.upperBound - 177) <= 1
				: abs(iconRange.lowerBound - 106) <= 1)
			#expect(dark ? titleRange.upperBound == 255 : titleRange.lowerBound == 26)
			#expect(button.imagePosition == .imageLeading)
			#expect(button.font?.pointSize == 13)
			button.highlight(true)
			let keyboardPress = try paint(
				button,
				dark: dark,
				tools: true
			)
			let restingPixel = try #require(keyboardPress.colorAt(
				x: 200,
				y: 20
			))
			#expect(abs(restingPixel.redComponent * 255 - CGFloat(dark ? 31 : 255)) <= 1)
			button.highlight(false)
			button.isEnabled = false
			let disabled = try paint(
				button,
				dark: dark,
				tools: true,
				scale: 2
			)
			let disabledTitle = paintedRedRange(
				disabled,
				in: cell.titleRect(forBounds: button.bounds)
			)
			#expect(dark ? disabledTitle.upperBound == 143 : disabledTitle.lowerBound == 140)
			button.isEnabled = true
		}
		var actionCount = 0
		controller.onOpenChanges =
		{
			actionCount += 1
		}
		button.performClick(nil)
		#expect(actionCount == 1)
	}

	@Test func selectedTabPaintsSuperellipseCornersAndBorderOverItsBacking() throws
	{
		let tab = ToolsTabSurface(isSelected: true)
		tab.frame = NSRect(
			x: 0,
			y: 0,
			width: 238,
			height: 32
		)
		for name: NSAppearance.Name in [.aqua, .darkAqua]
		{
			tab.appearance = NSAppearance(named: name)
			let dark = name == .darkAqua
			let bitmap = try paint(
				tab,
				dark: dark,
				scale: 2
			)
			let border = try #require(bitmap.colorAt(
				x: 238,
				y: 0
			)?.usingColorSpace(.sRGB))
			#expect(abs(border.redComponent * 255 - CGFloat(dark ? 69 : 237)) <= 1)
			// At (2.75, 2.75), the reference superellipse is painted; radius-10 circular
			// corners leave this pixel outside the surface. Bounds and radius stay fixed.
			let corner = try #require(bitmap.colorAt(
				x: 5,
				y: 5
			)?.usingColorSpace(.sRGB))
			#expect(dark ? corner.redComponent * 255 > 50 : corner.redComponent * 255 > 250)
		}
	}

	private func button(
		_ label: String,
		in view: NSView
	) -> NSButton?
	{
		if let button = view as? NSButton, button.accessibilityLabel() == label
		{
			return button
		}
		return view.subviews.lazy.compactMap
		{
			button(
				label,
				in: $0
			)
		}.first
	}

	private func paintedRedRange(
		_ bitmap: NSBitmapImageRep,
		in rect: NSRect
	) -> ClosedRange<Int>
	{
		var values: [Int] = []
		for y in Int(rect.minY * 2) ..< Int(rect.maxY * 2)
		{
			for x in Int(rect.minX * 2) ..< Int(rect.maxX * 2)
			{
				if let color = bitmap.colorAt(
					x: x,
					y: y
				)?.usingColorSpace(.sRGB)
				{
					values.append(Int((color.redComponent * 255).rounded()))
				}
			}
		}
		return (values.min() ?? 0) ... (values.max() ?? 0)
	}

	private func paint(
		_ tab: NSView,
		dark: Bool,
		tools: Bool = false,
		scale: CGFloat = 1
	) throws -> NSBitmapImageRep
	{
		let bitmap = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: Int(tab.bounds.width * scale),
			pixelsHigh: Int(tab.bounds.height * scale),
			bitsPerSample: 8,
			samplesPerPixel: 4,
			hasAlpha: true,
			isPlanar: false,
			colorSpaceName: .deviceRGB,
			bytesPerRow: 0,
			bitsPerPixel: 0
		))
		let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
		NSGraphicsContext.saveGraphicsState()
		defer
		{
			NSGraphicsContext.restoreGraphicsState()
		}
		NSGraphicsContext.current = context
		context.cgContext.scaleBy(
			x: scale,
			y: scale
		)
		tab.effectiveAppearance.performAsCurrentDrawingAppearance
		{
			NSColor(
				srgbRed: CGFloat(tools ? (dark ? 24 : 250) : (dark ? 36 : 246)) / 255,
				green: CGFloat(tools ? (dark ? 24 : 250) : (dark ? 36 : 246)) / 255,
				blue: CGFloat(tools ? (dark ? 24 : 250) : (dark ? 36 : 246)) / 255,
				alpha: 1
			).setFill()
			tab.bounds.fill()
			tab.draw(tab.bounds)
		}
		return bitmap
	}
}
