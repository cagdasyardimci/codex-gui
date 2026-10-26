import AppKit
import Testing

@testable import CodexGUI

@Suite(
	.serialized
) @MainActor
struct ComposerReferenceGeometryTests
{
	@Test func composerTextAndEnabledSendFillFollowAttachedWindowAppearance() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let controller = ConversationViewController()
			let window = NSWindow(
				contentRect: NSRect(
					x: -2000,
					y: -2000,
					width: 1000,
					height: 700
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			window.prepareForTesting()
			window.contentViewController = controller
			window.orderFront(nil)
			defer
			{
				window.close()
			}
			let snapshot = ConversationSnapshot(
				projectPath: "/tmp/replay",
				threads: [],
				selectedThreadID: nil,
				entries: [],
				canLoadEarlierTurns: false,
				changedFiles: [],
				diff: "",
				draft: "Ready",
				canSend: true,
				accountDescription: "Mock",
				backendDescription: "Mock",
				executionState: .ready,
				statusMessage: nil,
				models: [],
				selectedModelID: nil,
				selectedEffort: nil,
				pendingInteractions: [],
				recentProjects: []
			)
			controller.renderComposer(ConversationPresentation(snapshot).composer)
			#expect(controller.sendButton.isEnabled)

			for (appearance, primary, send) in [
				(NSAppearance.Name.aqua, 0x0D0D0D, 0x0D0D0D),
				(.darkAqua, 0xFFFFFF, 0x2C67C5),
				(.aqua, 0x0D0D0D, 0x0D0D0D),
			]
			{
				window.appearance = NSAppearance(named: appearance)
				window.displayIfNeeded()
				let editorColor = try #require(controller.composer.textColor)
				let insertionColor = try #require(
					controller.composer.insertionPointColor as? NSColor
				)
				let typingColor = try #require(
					controller.composer.typingAttributes[.foregroundColor] as? NSColor
				)
				let sendFill = try #require(controller.sendButton.layer?.backgroundColor)
				for color in [editorColor, insertionColor, typingColor]
				{
					#expect(try rgb(
						color,
						appearance: window.effectiveAppearance
					) == primary)
				}
				#expect(try rgb(
					try #require(NSColor(cgColor: sendFill)),
					appearance: window.effectiveAppearance
				) == send)
			}
		}
	}

	@Test func baselineCorrectionPreservesLineBoxesAndSelection() throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		_ = controller.view
		let editor = controller.composer
		editor.string = "First line\nSecond line"
		let selection = NSRange(
			location: 2,
			length: 3
		)
		editor.setSelectedRange(selection)
		let manager = try #require(editor.layoutManager)
		let container = try #require(editor.textContainer)
		manager.ensureLayout(for: container)

		let standard = NSTextView(frame: editor.bounds)
		standard.font = editor.font
		standard.defaultParagraphStyle = editor.defaultParagraphStyle
		standard.textContainerInset = .zero
		standard.textContainer?.lineFragmentPadding = 0
		standard.string = editor.string
		let standardManager = try #require(standard.layoutManager)
		let standardContainer = try #require(standard.textContainer)
		standardManager.ensureLayout(for: standardContainer)
		#expect(abs(standardManager.location(forGlyphAt: 0).y
				- manager.location(forGlyphAt: 0).y - 2) < 0.01)
		#expect(manager.lineFragmentRect(
			forGlyphAt: 0,
			effectiveRange: nil
		).height == 20)
		#expect(manager.usedRect(for: container).height
			== standardManager.usedRect(for: standardContainer).height)
		#expect(editor.selectedRange() == selection)

		editor.setMarkedText(
			"仮",
			selectedRange: NSRange(
				location: 0,
				length: 1
			),
			replacementRange: selection
		)
		#expect(editor.hasMarkedText())
		let markedSelection = editor.selectedRange()
		manager.ensureLayout(for: container)
		#expect(editor.markedRange() == NSRange(
			location: 2,
			length: 1
		))
		#expect(editor.selectedRange() == markedSelection)
		editor.unmarkText()
		#expect(!editor.hasMarkedText())
		#expect(editor.string == "Fi仮 line\nSecond line")
	}

	private func rgb(
		_ color: NSColor,
		appearance: NSAppearance
	) throws -> Int
	{
		var resolved: NSColor?
		appearance.performAsCurrentDrawingAppearance
		{
			resolved = color.usingColorSpace(.deviceRGB)
		}
		let rgb = try #require(resolved)
		return (Int((rgb.redComponent * 255).rounded()) << 16)
			| (Int((rgb.greenComponent * 255).rounded()) << 8)
			| Int((rgb.blueComponent * 255).rounded())
	}
}
