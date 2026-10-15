import AppKit
import Testing

@testable import CodexGUI

@Suite(
	.serialized
) @MainActor
struct ComposerReferenceGeometryTests
{
	@Test func editorAndFooterMatchReferenceAndMultilineUsesViewportCap() throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 1000,
				height: 881
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.appearance = NSAppearance(named: .aqua)
		window.contentViewController = controller
		window.setContentSize(NSSize(
			width: 1000,
			height: 881
		))
		controller.steerButton.isHidden = true
		controller.stopButton.isHidden = true
		controller.updateSendState()
		controller.modelEffortButton.update(
			summary: "GPT-6 Sol High",
			effortTitle: "High",
			fastMode: true,
			isPickerPresented: false
		)
		defer
		{
			window.close()
		}
		window.layoutIfNeeded()
		controller.view.layoutSubtreeIfNeeded()

		let surface = controller.composerSurface
		let editor = surface.convert(
			controller.composerScrollView.bounds,
			from: controller.composerScrollView
		)
		let footer = surface.convert(
			controller.addContextButton.alignmentRect(forFrame: controller.addContextButton.bounds),
			from: controller.addContextButton
		)
		#expect(surface.bounds.width == 736)
		#expect(surface.bounds.height == 98)
		#expect(editor.width == 712)
		#expect(editor.height == 44)
		#expect(editor.minX == 12)
		#expect(surface.bounds.maxY - editor.maxY == 14)
		#expect(editor.minY - footer.maxY == 4)
		#expect(footer.minX == 8)
		#expect(footer.minY == 8)
		#expect(controller.addContextButton.bounds.height == 28)
		#expect(controller.composer.textContainerOrigin == .zero)
		#expect(controller.composer.textContainer?.lineFragmentPadding == 0)
		#expect(controller.composer.defaultParagraphStyle?.minimumLineHeight == 20)
		let pane = controller.view.bounds
		let surfaceFrame = controller.view.convert(
			surface.bounds,
			from: surface
		)
		#expect(abs(surfaceFrame.midX - pane.midX) < 0.5)
		#expect(surfaceFrame.minY - pane.minY == 16)

		if let output = ProcessInfo.processInfo.environment["CODEX_GUI_COMPOSER_CAPTURE"]
		{
			try AppTestPNGWriter.write(
				surface,
				to: URL(fileURLWithPath: output)
			)
			controller.composer.string = "Do anything"
			controller.updateComposerHeight()
			controller.view.layoutSubtreeIfNeeded()
			try AppTestPNGWriter.write(
				surface,
				to: URL(fileURLWithPath: output + ".typed.png")
			)
		}

		controller.composer.string = Array(
			repeating: "Multiline draft",
			count: 30
		)
		.joined(separator: "\n")
		controller.updateComposerHeight()
		controller.view.layoutSubtreeIfNeeded()
		#expect(abs(controller.composerScrollView.bounds.height - 220.25) < 0.5)
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
}
