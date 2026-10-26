import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct DesktopActionRevealTests
{
	@Test func composerAndDiagramActionsRemainVisibleDuringDescendantKeyboardFocus() async throws
	{
		try await AppKitTestIsolation.perform
		{
			_ = NSApplication.shared
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
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
			let remove = NSButton(
				title: "Remove",
				target: nil,
				action: nil
			)
			let composer = ComposerImageAttachmentView(
				image: nil,
				previewButton: NSButton(),
				removeButton: remove
			)
			composer.frame = NSRect(
				x: 20,
				y: 20,
				width: 120,
				height: 120
			)
			let diagram = MarkdownDiagramControls(attachment: MarkdownRichAttachment(
				source: "graph TD; A --> B",
				lightImage: nil,
				darkImage: nil,
				isDiagram: true
			))
			diagram.frame = NSRect(
				x: 180,
				y: 20,
				width: 68,
				height: 32
			)
			let content = try #require(window.contentView)
			content.addSubview(composer)
			content.addSubview(diagram)
			let exit = try #require(NSEvent.otherEvent(
				with: .applicationDefined,
				location: .zero,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: 0,
				context: nil,
				subtype: 0,
				data1: 0,
				data2: 0
			))

			diagram.setHovered(false)
			#expect(remove.alphaValue == 0)
			#expect(diagram.alphaValue == 0)
			#expect(window.makeFirstResponder(remove))
			composer.mouseExited(with: exit)
			#expect(remove.alphaValue == 1)
			#expect(window.makeFirstResponder(diagram.optionsButton))
			composer.mouseExited(with: exit)
			diagram.setHovered(false)
			#expect(remove.alphaValue == 0)
			#expect(diagram.alphaValue == 1)
			#expect(window.makeFirstResponder(nil))
			diagram.setHovered(false)
			#expect(diagram.alphaValue == 0)
			diagram.setHovered(true)
			#expect(diagram.alphaValue == 1)
		}
	}
}
