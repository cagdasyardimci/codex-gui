import AppKit

@MainActor
final class DesktopSegmentedControl: NSSegmentedControl
{
	override var intrinsicContentSize: NSSize
	{
		NSSize(
			width: NSView.noIntrinsicMetric,
			height: super.intrinsicContentSize.height
		)
	}

	override func layout()
	{
		super.layout()
		guard bounds.width > 0, segmentCount > 0
		else
		{
			return
		}
		let segmentWidth = floor(max(
			1,
			bounds.width - 4
		) / CGFloat(segmentCount))
		for segment in 0 ..< segmentCount
		{
			if self.width(forSegment: segment) != segmentWidth
			{
				setWidth(
					segmentWidth,
					forSegment: segment
				)
			}
		}
	}
}
