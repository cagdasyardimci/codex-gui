import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct ConversationTerminalCardTests
{
	@Test func copyingRetainsExactCommandAndOutputUntilReuse()
	{
		_ = NSApplication.shared
		let card = ConversationTerminalCard()
		let command = command(output: "first\r\n\u{1b}[1msecond\u{1b}[0m\n👩🏽‍💻\n")
		card.configure(
			command,
			expanded: true,
			preserving: nil
		)
		let pasteboard = NSPasteboard.withUniqueName()
		defer
		{
			pasteboard.releaseGlobally()
		}
		card.writeCommand(to: pasteboard)
		#expect(pasteboard.string(forType: .string) == command.command)
		card.writeOutput(to: pasteboard)
		#expect(pasteboard.string(forType: .string) == command.output)
		card.configure(
			command,
			expanded: false,
			preserving: nil
		)
		#expect(card.readingPosition() == nil)
		card.writeCommand(to: pasteboard)
		#expect(pasteboard.string(forType: .string) == command.command)
		card.reset()
		pasteboard.clearContents()
		card.writeOutput(to: pasteboard)
		#expect(pasteboard.string(forType: .string) == nil)
		#expect(ConversationTerminalCard.sampledShellLineCount("a\r\nb\nc") == 3)
		#expect(ConversationTerminalCard.height(
			command: command,
			width: 400
		) <= 218)
	}

	@Test func appendedOutputPreservesSelectionAndScrollWhileReplacementResetsThem() throws
	{
		_ = NSApplication.shared
		let card = ConversationTerminalCard()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 400,
				height: 218
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		let host = try #require(window.contentView)
		card.translatesAutoresizingMaskIntoConstraints = false
		host.addSubview(card)
		NSLayoutConstraint.activate([
			card.leadingAnchor.constraint(equalTo: host.leadingAnchor),
			card.topAnchor.constraint(equalTo: host.topAnchor),
			card.widthAnchor.constraint(equalTo: host.widthAnchor),
		])
		defer
		{
			window.close()
		}
		let output = "\u{1b}[1m" + Array(
			repeating: String(
				repeating: "wide output ",
				count: 20
			),
			count: 40
		)
		.joined(separator: "\n") + "\u{1b}[0m"
		card.configure(
			command(output: output),
			expanded: true,
			preserving: nil
		)
		window.layoutIfNeeded()
		card.layoutContent(width: 400)
		card.restoreReadingPosition(ConversationTerminalCard.ReadingPosition(
			origin: NSPoint(
				x: 25,
				y: 80
			),
			selection: NSRange(
				location: 10,
				length: 10
			)
		))
		card.layoutContent(width: 400)
		let position = try #require(card.readingPosition())
		#expect(position.origin == NSPoint(
			x: 25,
			y: 80
		))
		#expect(position.selection == NSRange(
			location: 10,
			length: 10
		))
		card.configure(
			command(output: output + "\nTAIL"),
			expanded: true,
			preserving: position
		)
		window.layoutIfNeeded()
		card.layoutContent(width: 400)
		let retained = try #require(card.readingPosition())
		#expect(retained.origin == position.origin)
		#expect(retained.selection == position.selection)
		let text = try #require(descendants(card).compactMap
		{
			$0 as? NSTextView
		}.first)
		#expect(!text.string.contains("\u{1b}"))
		#expect((text.textStorage?.attribute(
			.font,
			at: 0,
			effectiveRange: nil
		) as? NSFont)?
			.fontName == "Menlo-Bold")
		NotificationCenter.default.post(
			name: TypographyPreferences.didChange,
			object: nil
		)
		NotificationCenter.default.post(
			name: ColorPreferences.didChange,
			object: nil
		)
		card.layoutContent(width: 400)
		#expect(card.readingPosition()?.selection == position.selection)
		#expect(card.readingPosition()?.origin == position.origin)
		#expect((text.textStorage?.attribute(
			.font,
			at: 0,
			effectiveRange: nil
		) as? NSFont)?
			.fontName == "Menlo-Bold")
		card.configure(
			command(output: "short"),
			expanded: true,
			preserving: nil
		)
		window.layoutIfNeeded()
		card.layoutContent(width: 400)
		let reset = try #require(card.readingPosition())
		#expect(reset.origin == .zero)
		#expect(reset.selection == NSRange(
			location: 0,
			length: 0
		))
	}

	private func command(output: String) -> ConversationCommand
	{
		ConversationCommand(
			command: "printf 'first\\nsecond'",
			cwd: "/tmp",
			output: output,
			status: "completed",
			exitCode: 0,
			durationMs: 100,
			actions: []
		)
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap(descendants)
	}
}
