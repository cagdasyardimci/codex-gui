import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct SettingsBrowserSitePanelTests
{
	@Test func sitePanelValidatesWithoutStatusOrErrorLabels() async throws
	{
		try await AppKitTestIsolation.perform
		{
			_ = NSApplication.shared
			let panel = SettingsBrowserSitePanel(
				site: nil,
				policy: [:],
				defaults: [:]
			)
			defer
			{
				panel.close()
			}
			let content = try #require(panel.contentView)
			let more = try #require(descendants(in: content).compactMap
			{
				$0 as? NSButton
			}.first
			{
				$0.title == "More options"
			})
			#expect(panel.contentView is DesktopDialogShell)
			let collapsedHeight = panel.contentRect(forFrameRect: panel.frame).height
			#expect(more.dispatchConfiguredAction())
			let expandedOptionsHeight = panel.contentRect(forFrameRect: panel.frame).height
			#expect(expandedOptionsHeight > collapsedHeight)

			let field = try #require(descendants(in: content).compactMap
			{
				$0 as? SettingsFormTextField
			}.first)
			field.stringValue = "https://example.com"
			panel.controlTextDidChange(Notification(
				name: NSControl.textDidChangeNotification,
				object: field
			))
			let expandedHeight = panel.contentRect(forFrameRect: panel.frame).height
			field.stringValue = "not a site"
			panel.controlTextDidChange(Notification(
				name: NSControl.textDidChangeNotification,
				object: field
			))
			#expect(field.hasValidationError)
			#expect(abs(panel.contentRect(forFrameRect: panel.frame).height - expandedHeight) < 1)

			for appearanceName in [NSAppearance.Name.aqua, .darkAqua]
			{
				panel.appearance = NSAppearance(named: appearanceName)
				let actual = try #require(field.textColor)
				let expected = AppKitColorTokens.settingsPrimaryText
				#expect(AppKitColorResolution.resolvedCGColor(
					actual,
					for: field
				).components
					== AppKitColorResolution.resolvedCGColor(
						expected,
						for: field
					).components)
			}
			#expect(!descendants(in: content).compactMap
			{
				$0 as? NSTextField
			}.contains
			{
				$0.stringValue == "These permissions match the defaults or the existing rule."
			})
			field.stringValue = "https://example.com"
			panel.controlTextDidChange(Notification(
				name: NSControl.textDidChangeNotification,
				object: field
			))
			#expect(!field.hasValidationError)
			#expect(abs(panel.contentRect(forFrameRect: panel.frame).height - expandedHeight) < 1)
		}
	}

	private func descendants(in view: NSView) -> [NSView]
	{
		view.subviews.flatMap
		{
			[$0] + descendants(in: $0)
		}
	}
}
