import Foundation

/// Preserves fractional title measurement and shares the cell's icon and title geometry.
struct PermissionControlLayout: Sendable
{
	let metrics: LayoutTokens.Permission

	init(metrics: LayoutTokens.Permission = LayoutTokens.permission)
	{
		self.metrics = metrics
	}

	func requestedWidth(titleWidth: CGFloat) -> CGFloat
	{
		titleWidth + metrics.titleHorizontalInset
	}

	func imageRect(in bounds: CGRect) -> CGRect
	{
		CGRect(
			x: bounds.minX + metrics.leadingInset,
			y: bounds.midY - metrics.iconSize / 2,
			width: metrics.iconSize,
			height: metrics.iconSize
		)
	}

	func titleRect(
		in bounds: CGRect,
		nativeTitleRect: CGRect
	) -> CGRect
	{
		CGRect(
			x: bounds.minX + metrics.titleLeadingInset,
			y: nativeTitleRect.minY,
			width: max(
				0,
				bounds.width - metrics.titleHorizontalInset
			),
			height: nativeTitleRect.height
		)
	}
}
