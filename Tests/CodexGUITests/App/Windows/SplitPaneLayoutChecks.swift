import AppKit
import Testing

/// Checks visible split viewports without counting collapsed panes' expansion constraints.
@MainActor
enum SplitPaneLayoutChecks
{
	static func verifyVisiblePanesFit(_ split: NSSplitViewController)
	{
		let visiblePaneFrames = split.splitViewItems.filter
		{
			!$0.isCollapsed
		}.map
		{
			let pane = $0.viewController.view
			return pane.convert(
				pane.bounds,
				to: split.view
			)
		}
		#expect(!visiblePaneFrames.isEmpty)
		#expect(visiblePaneFrames.allSatisfy
		{
			split.view.bounds.contains($0)
		})
		let visibleWidth = visiblePaneFrames.reduce(0)
		{
			$0 + $1.width
		}
		let dividerWidth = CGFloat(max(
			0,
			visiblePaneFrames.count - 1
		))
			* split.splitView.dividerThickness
		#expect(abs(visibleWidth + dividerWidth - split.view.bounds.width) < 1)
		#expect(split.view.fittingSize.height <= split.view.bounds.height + 1)
	}
}
