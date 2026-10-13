import AppKit
import CoreText
import Testing

@testable import CodexGUI

@Suite @MainActor
struct SidebarTypographyTests
{
	@Test func sidebarControlsRetainReferenceGlyphAdvances() throws
	{
		_ = NSApplication.shared
		let controller = NavigationViewController()
		_ = controller.view
		#expect(controller.newChatButton.title == "New chat")
		controller.sidebarItems = [.sectionHeader("Pinned"), .sectionHeader("Projects"), .showMore]
		var samples: [(String, NSFont, Double)] = [
			("New chat", try #require(controller.newChatButton.font), 61.203125),
		]
		for (row, width) in [45.46875, 54.2578125, 72.1640625].enumerated()
		{
			let cell = try #require(controller.tableView(
				controller.chatsTable,
				viewFor: nil,
				row: row
			) as? NSTableCellView)
			let field = try #require(textFields(in: cell).first)
			#expect(field is SidebarTextField)
			samples.append((field.stringValue, try #require(field.font), width))
		}
		let project = ProjectSidebarCellView(frame: .zero)
		let chat = TaskSidebarCellView(frame: .zero)
		#expect(project.textField is SidebarTextField)
		#expect(chat.textField is SidebarTextField)
		samples.append(("codex-gui", try #require(project.textField?.font), 65.34375))
		samples.append(("Use Chrome DevTools MCP", try #require(chat.textField?.font), 177.5703125))
		for (text, font, referenceWidth) in samples
		{
			let title = NSAttributedString(
				string: text,
				attributes: [.font: font]
			)
			let line = CTLineCreateWithAttributedString(title)
			#expect(font.pointSize == 14)
			#expect(abs(CTLineGetTypographicBounds(
				line,
				nil,
				nil,
				nil
			) - referenceWidth) < 0.02)
		}
	}

	@Test func sidebarAntialiasingReducesStrokeCoverageWithoutChangingFont() throws
	{
		_ = NSApplication.shared
		let ordinary = NSTextField(labelWithString: "Use Chrome DevTools MCP")
		let sidebar = SidebarTextField(labelWithString: ordinary.stringValue)
		for field in [ordinary, sidebar]
		{
			field.frame = NSRect(
				x: 0,
				y: 0,
				width: 240,
				height: 30
			)
			field.font = AppKitFontResolver.interfaceFont(ofSize: 14)
			field.textColor = .black
		}
		#expect(ordinary.font == sidebar.font)
		#expect(ordinary.intrinsicContentSize == sidebar.intrinsicContentSize)
		let ordinaryCoverage = try darkPixelCount(of: ordinary)
		let sidebarCoverage = try darkPixelCount(of: sidebar)
		#expect(sidebarCoverage > 0)
		#expect(sidebarCoverage < ordinaryCoverage)
	}

	private func textFields(in view: NSView) -> [NSTextField]
	{
		if let field = view as? NSTextField
		{
			return [field]
		}
		return view.subviews.flatMap
		{
			textFields(in: $0)
		}
	}

	private func darkPixelCount(of field: NSTextField) throws -> Int
	{
		let bitmap = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: 480,
			pixelsHigh: 60,
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
			x: 2,
			y: 2
		)
		context.cgContext.setShouldSmoothFonts(true)
		NSColor.white.setFill()
		field.bounds.fill()
		field.draw(field.bounds)
		var count = 0
		for y in 0 ..< bitmap.pixelsHigh
		{
			for x in 0 ..< bitmap.pixelsWide
			{
				let color = try #require(bitmap.colorAt(
					x: x,
					y: y
				)?.usingColorSpace(.deviceRGB))
				if (color.redComponent + color.greenComponent + color.blueComponent) / 3 < 0.78
				{
					count += 1
				}
			}
		}
		return count
	}
}
