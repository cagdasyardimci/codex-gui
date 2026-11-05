import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct SidebarBackgroundViewTests
{
	@Test func updatesMaterialForTheEffectiveAppearanceWithoutReplacingContent() throws
	{
		_ = NSApplication.shared
		let center = NotificationCenter()
		let opaque = ColorThemeProfile(
			background: 0,
			foreground: 0xffffff,
			accent: 0,
			contrast: 60,
			opaqueWindows: true
		)
		var configuration = ColorThemeConfiguration(
			light: .light,
			dark: opaque
		)
		let view = SidebarBackgroundView(
			configuration:
			{
				configuration
			},
			center: center
		)
		let content = NSView()
		view.addSubview(content)
		view.appearance = NSAppearance(named: .aqua)
		let material = try #require(view.subviews.compactMap
		{
			$0 as? NSVisualEffectView
		}.first)
		#expect(material.blendingMode == .behindWindow)
		#expect(!material.isHidden)
		view.appearance = NSAppearance(named: .darkAqua)
		#expect(material.isHidden)
		configuration = ColorThemeConfiguration(
			light: .light,
			dark: .dark
		)
		center.post(
			name: ColorPreferences.didChange,
			object: nil
		)
		#expect(!material.isHidden)
		configuration = ColorThemeConfiguration(
			light: .light,
			dark: opaque
		)
		center.post(
			name: ColorPreferences.didChange,
			object: nil
		)
		#expect(material.isHidden)
		#expect(content.superview === view)
	}
}
