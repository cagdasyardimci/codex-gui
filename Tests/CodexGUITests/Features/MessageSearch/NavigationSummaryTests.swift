import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct NavigationSummaryTests
{
	@Test func messageSearchDisplaysLoadedHistoryScope() throws
	{
		_ = NSApplication.shared
		let controller = MessageSearchController()
		let results = MessageSearchResults(
			query: "decision",
			scope: MessageSearchScope(
				loadedThreadCount: 1,
				totalThreadCount: 3,
				threadsWithEarlierTurns: 1
			),
			hits: []
		)
		controller.render(
			results,
			loading: false,
			unavailableReason: nil
		)
		let texts = navigationSubviews(of: controller.view).compactMap
		{
			($0 as? NSTextField)?.stringValue
		}
		#expect(texts.contains
		{
			$0.contains("Searching 1 of 3 listed conversations")
		})
		#expect(texts.contains
		{
			$0.contains("earlier turns to load")
		})
	}

	private func navigationSubviews(of view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap(navigationSubviews)
	}
}
