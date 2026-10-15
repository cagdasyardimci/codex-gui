import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationCodeCopyControlReuseTests
{
	@Test func streamedBodiesKeepButtonIdentityAndCopyTheCurrentExactUnicode() throws
	{
		_ = NSApplication.shared
		let item = ConversationCollectionItem()
		configure(
			item,
			code: ["old value\n", "second block\n"]
		)
		let first = buttons(in: item.view)
		try #require(first.count == 2)
		let body = "Unicode predecessor 😀\n\n```text\n  cafe\u{0301} 😀\tlatest  \n```"
			+ "\n\n```text\nsecond block\n```\n\nStreamed tail"
		configure(
			item,
			body: body
		)
		let next = buttons(in: item.view)
		try #require(next.count == 2)
		#expect(next[0] === first[0])
		#expect(next[1] === first[1])
		#expect(next.map(\.tag) == [0, 1])
		#expect(next[0].target === item)
		#expect(next[0].action == NSSelectorFromString("copyCode:"))
		#expect(next[0].accessibilityLabel() == "Copy code block 1")
		let pasteboard = NSPasteboard.withUniqueName()
		defer
		{
			pasteboard.releaseGlobally()
		}
		item.writeCodeBlock(
			from: next[0],
			to: pasteboard
		)
		let copied = try #require(pasteboard.string(forType: .string))
		#expect(copied.utf8.elementsEqual("  cafe\u{0301} 😀\tlatest  \n".utf8))
	}

	@Test func countChangesKeepSurvivingControlsAndDisconnectRemovedActions() throws
	{
		_ = NSApplication.shared
		let item = ConversationCollectionItem()
		configure(
			item,
			code: ["first\n", "second\n"]
		)
		let first = buttons(in: item.view)
		try #require(first.count == 2)
		configure(
			item,
			code: ["changed\n", "second\n", "third\n"]
		)
		let grown = buttons(in: item.view)
		try #require(grown.count == 3)
		#expect(grown[0] === first[0])
		#expect(grown[1] === first[1])
		#expect(grown[2].accessibilityLabel() == "Copy code block 3")
		configure(
			item,
			code: ["remaining\n"]
		)
		let shrunk = buttons(in: item.view)
		try #require(shrunk.count == 1)
		#expect(shrunk[0] === first[0])
		for removed in grown.dropFirst()
		{
			#expect(removed.superview == nil)
			#expect(removed.target == nil)
			#expect(removed.action == nil)
			#expect(removed.tag == -1)
		}
		let pasteboard = NSPasteboard.withUniqueName()
		defer
		{
			pasteboard.releaseGlobally()
		}
		pasteboard.setString(
			"Unchanged",
			forType: .string
		)
		item.writeCodeBlock(
			from: grown[1],
			to: pasteboard
		)
		#expect(pasteboard.string(forType: .string) == "Unchanged")
		item.writeCodeBlock(
			from: shrunk[0],
			to: pasteboard
		)
		#expect(pasteboard.string(forType: .string) == "remaining\n")
	}

	@Test func anotherEntryAndCollectionReuseDiscardOldControls() throws
	{
		_ = NSApplication.shared
		let item = ConversationCollectionItem()
		configure(
			item,
			code: ["owner one\n"]
		)
		let first = try #require(buttons(in: item.view).first)
		configure(
			item,
			code: ["owner two\n"],
			id: "other:reply"
		)
		let next = try #require(buttons(in: item.view).first)
		#expect(next !== first)
		#expect(first.target == nil && first.superview == nil)
		item.prepareForReuse()
		#expect(buttons(in: item.view).isEmpty)
		#expect(next.target == nil && next.superview == nil)
		configure(
			item,
			code: ["new lifetime\n"],
			id: "other:reply"
		)
		let reused = try #require(buttons(in: item.view).first)
		#expect(reused !== next)
		#expect(reused.tag == 0)
	}

	@Test func streamingKeepsKeyboardFocusAndMovesButtonGeometryWithItsBlock() throws
	{
		_ = NSApplication.shared
		let item = ConversationCollectionItem()
		configure(
			item,
			code: ["first\n", "second\n"]
		)
		item.view.frame = NSRect(
			x: 0,
			y: 0,
			width: 480,
			height: 600
		)
		let window = NSWindow(
			contentRect: item.view.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentViewController = item
		window.setContentSize(item.view.frame.size)
		defer
		{
			window.contentViewController = nil
			window.close()
		}
		item.view.layoutSubtreeIfNeeded()
		let first = try #require(buttons(in: item.view).first)
		let textView = try #require(findTextView(in: item.view))
		let initialFrame = textView.convert(
			first.bounds,
			from: first
		)
		let initialLineY = try codeLineOrigin(in: textView)
		#expect(window.makeFirstResponder(first))
		configure(
			item,
			body: "New predecessor\n\nMore predecessor\n\n"
				+ "```text\nfirst\n```\n\n```text\nsecond\n```"
		)
		item.view.layoutSubtreeIfNeeded()
		let updated = try #require(buttons(in: item.view).first)
		let updatedFrame = textView.convert(
			updated.bounds,
			from: updated
		)
		let updatedLineY = try codeLineOrigin(in: textView)
		#expect(updated === first)
		#expect(window.firstResponder === first)
		// Text coordinates increase downward; the button's parent NSView is unflipped.
		#expect(updatedFrame.minY > initialFrame.minY)
		#expect(abs((updatedFrame.minY - initialFrame.minY) - (updatedLineY - initialLineY)) < 1)
		#expect(updatedFrame.size == initialFrame.size)
	}

	private func configure(
		_ item: ConversationCollectionItem,
		code: [String],
		id: String = "turn:reply"
	)
	{
		configure(
			item,
			body: code.map
			{
				"```text\n" + $0 + "```"
			}.joined(separator: "\n\n"),
			id: id
		)
	}

	private func configure(
		_ item: ConversationCollectionItem,
		body: String,
		id: String = "turn:reply"
	)
	{
		let content = PreparedConversationContent(MarkdownContentParser.parse(
			body,
			markdown: true
		))
		item.configure(
			ConversationEntry(
				id: id,
				kind: .agent,
				title: "Codex",
				body: body
			),
			content: content,
			expanded: true,
			onToggle:
			{
			}
		)
	}

	private func buttons(in view: NSView) -> [NSButton]
	{
		var found = view.subviews.flatMap
		{
			buttons(in: $0)
		}
		if let button = view as? NSButton,
			button.accessibilityLabel()?.hasPrefix("Copy code block ") == true
		{
			found.append(button)
		}
		return found.sorted
		{
			$0.tag < $1.tag
		}
	}

	private func findTextView(in view: NSView) -> NSTextView?
	{
		if let text = view as? NSTextView
		{
			return text
		}
		return view.subviews.lazy.compactMap
		{
			findTextView(in: $0)
		}.first
	}

	private func codeLineOrigin(in textView: NSTextView) throws -> CGFloat
	{
		let range = (textView.string as NSString).range(of: "first")
		try #require(range.location != NSNotFound)
		let layout = try #require(textView.layoutManager)
		let container = try #require(textView.textContainer)
		layout.ensureLayout(for: container)
		return layout.lineFragmentRect(
			forGlyphAt: layout.glyphIndexForCharacter(at: range.location),
			effectiveRange: nil
		).minY + textView.textContainerOrigin.y
	}
}
