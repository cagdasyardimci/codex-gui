import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationReferencePresentationTests
{
	private let body = """
	Completed the audit with **10 subagents** covering **988 Swift test functions**.

	Found **5 High, 22 Medium and 3 Low** verification gaps. The High findings concern:

	- Permission buttons’ turn/session grant scope.
	- Approval payload forwarding through the runtime.
	- Decision correlation for mixed request ID types.
	- Committed-work preservation during cancellation.
	- A parser test that requires known incorrect line numbers.

	Execution: **985 passed, 3 layout tests failed** across isolated runs. Grouped runs \
	also ended incompletely, so **`make check` remains failing**. All 18 Python tests \
	and synthetic backend checks passed.

	The [full audit report](/tmp/audit.md) includes locations, evidence, escaped \
	defects, scoped remediation, inventories and logs. Suspicions are separate from \
	confirmed findings.

	No production code or tests were modified.
	"""

	@Test func referenceMessagePreservesCopyAndMeasuresAtNarrowAndWideWidths() async throws
	{
		_ = NSApplication.shared
		let content = await ConversationContentCache().content(
			body: body,
			markdown: true
		)
		let item = ConversationCollectionItem()
		item.configure(
			ConversationEntry(
				id: "turn:reply",
				kind: .agent,
				title: "Codex",
				body: body
			),
			content: content,
			expanded: false,
			onToggle:
			{
			}
		)
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 736,
				height: 450
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.appearance = NSAppearance(named: .darkAqua)
		window.contentViewController = item
		for width: CGFloat in [320, 736]
		{
			let size = ConversationCollectionItem.itemSize(
				content: content,
				width: width,
				expandable: false
			)
			window.setContentSize(size)
			item.view.layoutSubtreeIfNeeded()
			let textView = try #require(findText(in: item.view))
			let layout = try #require(textView.layoutManager)
			let container = try #require(textView.textContainer)
			layout.ensureLayout(for: container)
			#expect(layout.usedRect(for: container).maxY <= textView.bounds.height)
			let first = (textView.string as NSString).range(of: "Permission")
			let second = (textView.string as NSString).range(of: "Approval")
			let firstGlyph = layout.glyphIndexForCharacter(at: first.location)
			let secondGlyph = layout.glyphIndexForCharacter(at: second.location)
			#expect(abs(layout.location(forGlyphAt: firstGlyph).x - layout
					.location(forGlyphAt: secondGlyph).x) < 0.5)
			textView.selectAll(nil)
			let pasteboard = NSPasteboard.withUniqueName()
			#expect(textView.writeSelection(
				to: pasteboard,
				type: .string
			))
			let copied = try #require(pasteboard.string(forType: .string))
			#expect(copied.contains("• Permission"))
			#expect(copied.contains("The full audit report"))
			#expect(!copied.contains("\u{FFFC}"))
			#expect(!copied.contains("\t"))
		}
		if let output = ProcessInfo.processInfo.environment["CODEX_GUI_REFERENCE_PREVIEW"]
		{
			findText(in: item.view)?.setSelectedRange(NSRange(
				location: 0,
				length: 0
			))
			let size = item.view.bounds.size
			let surface = NSView(frame: NSRect(
				x: 0,
				y: 0,
				width: size.width + 43,
				height: size.height + 93
			))
			surface.wantsLayer = true
			surface.layer?.backgroundColor = NSColor(
				srgbRed: 24.0 / 255,
				green: 24.0 / 255,
				blue: 24.0 / 255,
				alpha: 1
			).cgColor
			surface.appearance = NSAppearance(named: .darkAqua)
			item.view.frame.origin = NSPoint(
				x: 36,
				y: 86
			)
			surface.addSubview(item.view)
			let change = try #require(FileChange(json: [
				"path": "/tmp/build-codex-test-audit.py",
				"kind": "update",
				"diff": "@@ -0,0 +1,172 @@\n" + String(
					repeating: "+fixture\n",
					count: 172
				),
			]))
			let card = ConversationFileChangeCollectionItem()
			card.configure(
				[change],
				status: "completed"
			)
			card.view.frame = NSRect(
				x: 36,
				y: 12,
				width: size.width,
				height: 66
			)
			surface.addSubview(card.view)
			card.view.layoutSubtreeIfNeeded()
			let bitmap = try #require(surface.bitmapImageRepForCachingDisplay(in: surface.bounds))
			surface.cacheDisplay(
				in: surface.bounds,
				to: bitmap
			)
			try #require(bitmap.representation(
				using: .png,
				properties: [:]
			))
			.write(to: URL(fileURLWithPath: output))
		}
	}

	@Test func reportedEditsFollowReplyAndStayInsideTheirTurn() async throws
	{
		let change = try #require(FileChange(json: [
			"path": "/tmp/a.py",
			"kind": "update",
			"diff": "@@ -1 +1 @@\n-old\n+new"
		]))
		let entries = [
			ConversationEntry(
				id: "one:edit",
				kind: .tool,
				title: "Changes",
				body: "a.py",
				activity: .fileChanges(
					[change],
					status: "completed"
				)
			),
			ConversationEntry(
				id: "one:reply",
				kind: .agent,
				title: "Codex",
				body: "Done"
			),
			ConversationEntry(
				id: "two:user",
				kind: .user,
				title: "You",
				body: "Next"
			),
		]
		let prepared = try #require(await ConversationNetFileChangePreparation().prepare(
			TranscriptPreparationCoordinator.fileChangeSources(from: entries),
			context: "reported-edits"
		))
		let rows = ConversationTranscriptRow.make(
			entries: entries,
			timings: [ConversationTurnTiming(
				turnID: "one",
				status: "completed"
			)],
			projectPath: "/tmp",
			preparedNetChanges: prepared
		)
		#expect(rows.map(\.id) == ["one:reply", "one:file-change-summary", "two:user"])
		let card = ConversationFileChangeCollectionItem()
		card.configure(
			[change],
			status: "completed"
		)
		#expect(card.view.accessibilityLabel() == "Edited a.py")
	}

	private func findText(in view: NSView) -> NSTextView?
	{
		if let text = view as? NSTextView
		{
			return text
		}
		return view.subviews.lazy.compactMap
		{
			findText(in: $0)
		}.first
	}
}
