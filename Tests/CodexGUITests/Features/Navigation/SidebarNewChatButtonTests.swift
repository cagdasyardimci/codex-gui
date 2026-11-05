import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct SidebarNewChatButtonTests
{
	@Test
	func titleTracksOwningWindowAppearanceAndThemeRefresh() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let center = NotificationCenter()
			let button = SidebarNewChatButton(center: center)
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 220,
					height: 80
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
			window.contentView?.addSubview(button)
			@MainActor func checkColor(_ mode: ColorAppearance) throws
			{
				let textColor = try #require(button.attributedTitle.attribute(
					.foregroundColor,
					at: 0,
					effectiveRange: nil
				) as? NSColor)
				let color = try #require(textColor.usingColorSpace(.sRGB))
				let theme = ColorPreferences().configuration
				let profile = mode == .dark ? theme.dark : theme.light
				let expected = try #require(ColorPalette(
					configuration: profile,
					mode: mode
				)
				.foreground.usingColorSpace(.sRGB))
				#expect(abs(color.redComponent - expected.redComponent) < 0.001)
				#expect(abs(color.greenComponent - expected.greenComponent) < 0.001)
				#expect(abs(color.blueComponent - expected.blueComponent) < 0.001)
			}
			@MainActor func check(_ mode: ColorAppearance) throws
			{
				window.appearance = NSAppearance(named: mode == .dark ? .darkAqua : .aqua)
				window.contentView?.layoutSubtreeIfNeeded()
				#expect(button.effectiveAppearance
					.bestMatch(from: [.darkAqua, .aqua]) == (mode == .dark ? .darkAqua : .aqua))
				try checkColor(mode)
			}
			try check(.light)
			try check(.dark)
			try check(.light)
			let corrupted = NSMutableAttributedString(attributedString: button.attributedTitle)
			corrupted.addAttribute(
				.foregroundColor,
				value: NSColor.systemPink,
				range: NSRange(
					location: 0,
					length: corrupted.length
				)
			)
			button.attributedTitle = corrupted
			center.post(
				name: ColorPreferences.didChange,
				object: nil
			)
			try checkColor(.light)
		}
	}
	@Test func titleStaysLeadingAfterInitialTypographyAndRefresh() throws
	{
		_ = NSApplication.shared
		let button = SidebarNewChatButton()
		func checkTitle() throws
		{
			#expect(button.alignment == .left)
			let paragraph = try #require(button.attributedTitle.attribute(
				.paragraphStyle,
				at: 0,
				effectiveRange: nil
			) as? NSParagraphStyle)
			#expect(paragraph.alignment == .left)
			let cell = try #require(button.cell as? NewChatButtonCell)
			let bounds = NSRect(
				x: 0,
				y: 0,
				width: 220,
				height: 30
			)
			#expect(cell.titleRect(forBounds: bounds).minX == cell.imageRect(forBounds: bounds).maxX
				+ NavigationSidebarLayout.iconTextSpacing)
		}
		try checkTitle()
		let center = NotificationCenter()
		var configuration = TypographyConfiguration(uiSize: 11)
		button.setTypographyRole(
			TypographyTokens.Sidebar.row,
			configuration:
			{
				configuration
			},
			center: center
		)
		configuration = TypographyConfiguration(uiSize: 16)
		center.post(
			name: TypographyPreferences.didChange,
			object: nil
		)
		try checkTitle()
	}
}
