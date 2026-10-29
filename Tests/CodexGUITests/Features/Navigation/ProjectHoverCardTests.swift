import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct ProjectHoverCardTests
{
	@Test func projectHoverCardPreservesMetadataAppearanceAndFocusThroughItsLifecycle() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let window = NSWindow(
				contentRect: NSRect(
					x: 100,
					y: 100,
					width: 400,
					height: 240
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
			let anchor = ProjectSidebarCellView(frame: NSRect(
				x: 20,
				y: 80,
				width: 180,
				height: 30
			))
			try #require(window.contentView).addSubview(anchor)
			window.orderFront(nil)
			let responder = window.firstResponder
			var edits = 0
			let card = ProjectHoverCard(
				project: URL(fileURLWithPath: "/tmp/hover-project"),
				name: "Hover Project",
				isPinned: false,
				loadedTaskCount: 2,
				activeTaskCount: 1,
				onTogglePin:
				{
				},
				onEditProject:
				{
					edits += 1
				}
			)
			defer
			{
				card.dismiss()
			}
			card.show(beside: anchor)
			let panel = try #require(card.panel)
			#expect(panel.parent === window)
			#expect(window.firstResponder === responder)
			let labels = descendants(card.content).compactMap
			{
				$0 as? NSTextField
			}
			.map(\.stringValue)
			#expect(labels.contains("Hover Project"))
			#expect(labels.contains("2 chats · 1 active"))
			#expect(labels.contains("/tmp/hover-project"))
			for theme: NSAppearance.Name in [.aqua, .darkAqua, .aqua]
			{
				window.appearance = NSAppearance(named: theme)
				#expect(card.panel === panel)
				#expect(card.content.effectiveAppearance
					.bestMatch(from: [.aqua, .darkAqua]) == theme)
			}
			let edit = try #require(descendants(card.content).compactMap
			{
				$0 as? NSButton
			}
			.first
			{
				$0.title == "Edit project"
			})
			#expect(edit.dispatchConfiguredAction())
			#expect(edits == 1)
			#expect(card.panel == nil)
			#expect(window.firstResponder === responder)

			anchor.hoverCard = card
			anchor.setHovered(true)
			let firstPanel = try #require(card.panel)
			anchor.setHovered(false)
			let exit = try #require(card.pendingDismissal)
			anchor.setHovered(true)
			await exit.value
			#expect(card.pendingDismissal == nil)
			#expect(card.panel === firstPanel)
			#expect(firstPanel.parent === window)

			window.setContentSize(NSSize(
				width: 420,
				height: 260
			))
			#expect(card.panel == nil)
			#expect(firstPanel.parent == nil)
			card.show(beside: anchor)
			let replacementPanel = try #require(card.panel)
			#expect(replacementPanel !== firstPanel)
			anchor.hoverCard = nil
			#expect(card.panel == nil)
			#expect(replacementPanel.parent == nil)

			anchor.hoverCard = card
			card.show(beside: anchor)
			let detachedPanel = try #require(card.panel)
			anchor.removeFromSuperview()
			#expect(card.panel == nil)
			#expect(detachedPanel.parent == nil)
			try #require(window.contentView).addSubview(anchor)
			card.show(beside: anchor)
			let closingPanel = try #require(card.panel)
			window.close()
			#expect(card.panel == nil)
			#expect(closingPanel.parent == nil)
		}
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		view.subviews + view.subviews.flatMap
		{
			descendants($0)
		}
	}
}
