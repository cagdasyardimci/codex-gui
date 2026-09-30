import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct BackendDetailsViewTests
{
	@Test func longReportWrapsAndCanScrollToItsFinalLineAfterResizing() throws
	{
		let report = (1 ... 150)
			.map
			{
				"Line \($0): " + String(
					repeating: "diagnostic ",
					count: 12
				)
			}
			.joined(separator: "\n")
		let scrollView = BackendDetailsView(report: report)
		let textView = try #require(scrollView.documentView as? NSTextView)
		let layout = try #require(textView.layoutManager)
		let container = try #require(textView.textContainer)

		for width in [500.0, 320.0, 600.0]
		{
			scrollView.setFrameSize(NSSize(
				width: width,
				height: 240
			))
			scrollView.layoutSubtreeIfNeeded()
			layout.ensureLayout(for: container)
			#expect(abs(textView.frame.width - scrollView.contentSize.width) < 1)
			#expect(layout.usedRect(for: container).height <= textView.frame.height)
			#expect(textView.frame.height > scrollView.contentSize.height)

			textView.scrollRangeToVisible(NSRange(
				location: (report as NSString).length - 1,
				length: 1
			))
			#expect(scrollView.contentView.bounds.minY > 0)
			#expect(textView.visibleRect.maxY >= textView.bounds.maxY - 20)
		}
		#expect(textView.string == report)
	}
}
