import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct DesktopResourceRowTests
{
	@Test func replacedAttachmentRowsCannotRemoveTheCurrentResource() throws
	{
		_ = NSApplication.shared
		let context = ComposerContextView()
		let original = ComposerContextItem(
			id: "resource",
			kind: .fileReference,
			title: "Original.swift",
			path: "/project/Original.swift"
		)
		var removed: [String] = []
		context.onRemove =
		{
			removed.append($0)
		}
		context.render(items: [original])
		let first = try #require(resourceRows(in: context).first)
		let staleRemove = try #require(first.actionButtons.first
		{
			$0.title == "Remove"
		})
		try #require(staleRemove.dispatchConfiguredAction())
		#expect(removed == ["resource"])

		let replacement = ComposerContextItem(
			id: "resource",
			kind: .textExcerpt,
			title: "Updated.swift",
			path: "/project/Updated.swift",
			firstLine: 4,
			lastLine: 7,
			excerpt: "let value = 1"
		)
		context.render(items: [replacement])
		let current = try #require(resourceRows(in: context).first)
		#expect(current !== first)
		#expect(current.titleLabel.stringValue == "Updated.swift")
		#expect(current.detailLabel?
			.stringValue == "Code excerpt: /project/Updated.swift · lines 4–7")
		try #require(staleRemove.dispatchConfiguredAction())
		#expect(removed == ["resource"])
		let currentRemove = try #require(current.actionButtons.first
		{
			$0.title == "Remove"
		})
		try #require(currentRemove.dispatchConfiguredAction())
		#expect(removed == ["resource", "resource"])

		context.render(items: [])
		try #require(currentRemove.dispatchConfiguredAction())
		#expect(removed == ["resource", "resource"])
	}

	private func resourceRows(in view: NSView) -> [DesktopResourceRow]
	{
		if let row = view as? DesktopResourceRow
		{
			return [row]
		}
		return view.subviews.flatMap
		{
			resourceRows(in: $0)
		}
	}
}
