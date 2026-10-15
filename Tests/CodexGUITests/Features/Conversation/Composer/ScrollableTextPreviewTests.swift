import AppKit
import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct ScrollableTextPreviewTests
{
	@Test func codePreviewHasUsableDocumentSizeAndTracksResize()
	{
		_ = NSApplication.shared
		let contents = (1 ... 120).map
		{
			"line \($0): let value = \($0)"
		}.joined(separator: "\n")
		let preview = ScrollableTextPreview.make(
			text: contents,
			size: NSSize(
				width: 540,
				height: 300
			),
			font: .monospacedSystemFont(
				ofSize: 12,
				weight: .regular
			),
			accessibilityLabel: "Select code lines"
		)
		preview.scrollView.layoutSubtreeIfNeeded()
		#expect(preview.textView.frame.width > 400)
		#expect(preview.textView.frame.height > preview.scrollView.contentSize.height)
		#expect(preview.textView.textContainer?.widthTracksTextView == true)
		let selection = (contents as NSString).range(of: "line 75: let value = 75")
		preview.textView.setSelectedRange(selection)
		#expect(
			CodeRangeSelection.item(
				path: "Example.swift",
				contents: contents,
				selectedRange: preview.textView.selectedRange()
			)?.firstLine == 75
		)

		preview.scrollView.setFrameSize(NSSize(
			width: 320,
			height: 200
		))
		preview.scrollView.layoutSubtreeIfNeeded()
		#expect(abs(preview.textView.frame.width - preview.scrollView.contentSize.width) < 2)
	}
}
