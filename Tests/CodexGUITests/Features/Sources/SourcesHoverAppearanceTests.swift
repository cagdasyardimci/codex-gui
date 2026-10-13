import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite(.serialized)
struct SourcesHoverAppearanceTests
{
	@Test func shownPreviewTracksInheritedWindowAppearanceAndDismissalStopsBinding() async throws
	{
		_ = NSApplication.shared
		let applicationAppearance = NSApp.appearance
		let parent = HoverSchedulingWindow(
			contentRect: NSRect(
				x: -2000,
				y: -2000,
				width: 400,
				height: 200
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		parent.isReleasedWhenClosed = false
		let anchor = NSButton(
			title: "Sources",
			target: nil,
			action: nil
		)
		anchor.frame = NSRect(
			x: 20,
			y: 80,
			width: 100,
			height: 30
		)
		try #require(parent.contentView).addSubview(anchor)
		let preview = SourcesTabHoverPreview()
		defer
		{
			preview.dismiss()
			parent.close()
			NSApp.appearance = applicationAppearance
		}
		NSApp.appearance = NSAppearance(named: .aqua)
		#expect(parent.isKeyWindow)
		#expect(parent.makeFirstResponder(anchor))
		preview.show(
			sources: ConversationLocalSources(entries: []),
			below: anchor
		)
		try await Task.sleep(for: .milliseconds(350))
		let panel = try #require(parent.childWindows?.first)
		let content = try #require(panel.contentView)
		#expect(panel.isVisible)
		let frame = panel.frame
		var backgrounds: [CGColor] = []
		for name: NSAppearance.Name in [.darkAqua, .aqua, .darkAqua, .aqua]
		{
			NSApp.appearance = NSAppearance(named: name)
			#expect(content.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == name)
			#expect(parent.childWindows?.first === panel)
			#expect(panel.contentView === content)
			#expect(panel.frame == frame)
			#expect(parent.firstResponder === anchor)
			let background = try #require(content.layer?.backgroundColor)
			#expect(background == AppKitColorResolution.resolvedCGColor(
				.controlBackgroundColor,
				for: content
			))
			backgrounds.append(background)
		}
		#expect(backgrounds[0] != backgrounds[1])
		#expect(backgrounds[0] == backgrounds[2])
		anchor.appearance = NSAppearance(named: .darkAqua)
		#expect(content.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
		preview.dismiss()
		#expect(!panel.isVisible)
		#expect(parent.childWindows?.isEmpty != false)
		let dismissedAppearance = panel.effectiveAppearance.name
		anchor.appearance = NSAppearance(named: .aqua)
		#expect(panel.effectiveAppearance.name == dismissedAppearance)
		preview.show(
			sources: ConversationLocalSources(entries: []),
			below: anchor
		)
		preview.dismiss()
		try await Task.sleep(for: .milliseconds(300))
		#expect(parent.childWindows?.isEmpty != false)
	}

	@MainActor
	private final class HoverSchedulingWindow: NSWindow
	{
		// The test host need not activate the process to exercise the delayed hover presentation.
		override var isKeyWindow: Bool
		{
			true
		}
	}
}
