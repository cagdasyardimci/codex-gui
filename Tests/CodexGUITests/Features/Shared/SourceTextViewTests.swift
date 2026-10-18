import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct SourceTextViewTests
{
	@Test func sharedViewportKeepsFileEditingSeparateFromDiffSelection() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let file = FileSourceView()
			file.render(
				text: "file text",
				path: "example.txt",
				editable: true
			)
			let diff = GitUnifiedCodeView(
				rows: [GitDiffRow(
					id: "one",
					kind: .context,
					text: "diff text",
					oldLine: 1,
					newLine: 1
				)],
				path: "example.txt"
			)
			let diffText = try #require(text(in: diff))
			#expect(file.textView.isEditable)
			#expect(file.textView.allowsUndo)
			#expect(file.textView.usesFindBar)
			#expect(!diffText.isEditable)
			#expect(diffText.isSelectable)
			diffText.setSelectedRange(NSRange(
				location: 0,
				length: 4
			))
			diffText.insertText(
				"changed",
				replacementRange: diffText.selectedRange()
			)
			#expect(diffText.string == "diff text")
			file.textView.insertText(
				"edited ",
				replacementRange: NSRange(
					location: 0,
					length: 0
				)
			)
			#expect(file.textView.string == "edited file text")
			#expect(diffText.selectedRange().length == 4)
		}
	}

	@Test func filesAndChangesRenderTheSameSourceAcrossAppearanceAndWrapping() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let lines = [
				"# Heading",
				"1. plain **strong** and `code`",
				String(
					repeating: "wrapped source words ",
					count: 8
				),
				"ordinary text"
			]
			let content = lines.joined(separator: "\n")
			let file = FileSourceView()
			file.render(
				text: content,
				path: "notes.md",
				editable: true
			)
			let changes = GitUnifiedCodeView(
				rows: lines.enumerated().map
				{
					GitDiffRow(
						id: "\($0.offset)",
						kind: .context,
						text: $0.element,
						oldLine: $0.offset + 1,
						newLine: $0.offset + 1
					)
				},
				path: "notes.md",
				gutterMode: .new
			)
			changes.wrapsCode = true
			let windows = [file, changes].map
			{
				view in
				let window = NSWindow(
					contentRect: NSRect(
						x: 0,
						y: 0,
						width: 420,
						height: 300
					),
					styleMask: [.titled],
					backing: .buffered,
					defer: false
				)
				window.isReleasedWhenClosed = false
				window.contentView = view
				return window
			}
			defer
			{
				windows.forEach
				{
					$0.close()
				}
			}
			let changeText = try #require(text(in: changes))
			let fileText = file.textView
			let selection = NSRange(
				location: 2,
				length: 3
			)
			[fileText, changeText].forEach
			{
				$0.setSelectedRange(selection)
			}
			for appearance in [NSAppearance.Name.aqua, .darkAqua, .aqua]
			{
				for window in windows
				{
					window.appearance = NSAppearance(named: appearance)
					window.contentView?.layoutSubtreeIfNeeded()
				}
				let fileStorage = try #require(fileText.textStorage)
				let changeStorage = try #require(changeText.textStorage)
				#expect(fileStorage.string == content)
				#expect(changeStorage.string == content)
				for offset in 0 ..< fileStorage.length
				{
					let fileFont = try #require(fileStorage.attribute(
						.font,
						at: offset,
						effectiveRange: nil
					) as? NSFont)
					let changeFont = try #require(changeStorage.attribute(
						.font,
						at: offset,
						effectiveRange: nil
					) as? NSFont)
					#expect(fileFont == changeFont)
					#expect(fileFont.pointSize == 13)
					let fileColor = try #require(fileStorage.attribute(
						.foregroundColor,
						at: offset,
						effectiveRange: nil
					) as? NSColor)
					let changeColor = try #require(changeStorage.attribute(
						.foregroundColor,
						at: offset,
						effectiveRange: nil
					) as? NSColor)
					#expect(fileColor == changeColor)
				}
				for textView in [fileText, changeText]
				{
					let manager = try #require(textView.layoutManager)
					let container = try #require(textView.textContainer)
					manager.ensureLayout(for: container)
					var fragments = 0
					manager.enumerateLineFragments(forGlyphRange:
						NSRange(
							location: 0,
							length: manager.numberOfGlyphs
						))
					{
						rect, _, _, _, _ in
						#expect(abs(rect.height - 22) < 0.5)
						fragments += 1
					}
					#expect(fragments > lines.count)
					#expect(textView.selectedRange() == selection)
				}
				if let directory = ProcessInfo.processInfo.environment["CODEX_FILES_QA_DIR"]
				{
					for (name, view) in [("files", file as NSView), ("changes", changes as NSView)]
					{
						try AppTestPNGWriter.write(
							view,
							to: URL(fileURLWithPath: directory)
								.appendingPathComponent("shared-\(name)-\(appearance.rawValue).png")
						)
					}
				}
				windows.forEach
				{
					$0.setContentSize(NSSize(
						width: 300,
						height: 300
					))
				}
			}
		}
	}

	private func text(in view: NSView) -> NSTextView?
	{
		if let text = view as? NSTextView
		{
			return text
		}
		return view.subviews.lazy.compactMap
		{
			text(in: $0)
		}.first
	}
}
