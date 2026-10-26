import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct SettingsBrowserSitePanelTests
{
	@Test func sitePanelResizesForExpandedOptionsAndValidationError() async throws
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
			let status = try #require(descendants(in: content).compactMap
			{
				$0 as? NSTextField
			}.first
			{
				$0.stringValue == "These permissions match the defaults or the existing rule."
			})
			#expect(!status.isHiddenOrHasHiddenAncestor)
			let expandedHeight = panel.contentRect(forFrameRect: panel.frame).height
			field.stringValue = "not a site"
			panel.controlTextDidChange(Notification(
				name: NSControl.textDidChangeNotification,
				object: field
			))
			#expect(field.hasValidationError)
			#expect(status.isHidden)
			#expect(panel.contentRect(forFrameRect: panel.frame).height > expandedHeight)

			for (appearanceName, expectedWhite) in [
				(NSAppearance.Name.aqua, false),
				(NSAppearance.Name.darkAqua, true),
			]
			{
				panel.appearance = NSAppearance(named: appearanceName)
				var actual: NSColor?
				field.effectiveAppearance.performAsCurrentDrawingAppearance
				{
					actual = field.textColor?.usingColorSpace(.deviceRGB)
				}
				let color = try #require(actual)
				let expected: CGFloat = expectedWhite ? 1 : 13.0 / 255.0
				#expect(abs(color.redComponent - expected) < 0.001)
				#expect(abs(color.greenComponent - expected) < 0.001)
				#expect(abs(color.blueComponent - expected) < 0.001)
			}
			let error = try #require(descendants(in: content).compactMap
			{
				$0 as? SettingsFormErrorLabel
			}.first
			{
				$0.accessibilityLabel() == "Site validation error"
			})
			#expect(!error.isHidden)
			field.stringValue = "https://example.com"
			panel.controlTextDidChange(Notification(
				name: NSControl.textDidChangeNotification,
				object: field
			))
			#expect(!field.hasValidationError)
			#expect(error.isHidden)
			#expect(!status.isHiddenOrHasHiddenAncestor)
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
