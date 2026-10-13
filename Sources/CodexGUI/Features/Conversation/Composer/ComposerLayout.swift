import Foundation

/// Pure composer policies; native measurement and constraint updates remain with their views.
struct ComposerLayout: Sendable
{
	let metrics: LayoutTokens.Composer

	init(metrics: LayoutTokens.Composer = LayoutTokens.composer)
	{
		self.metrics = metrics
	}

	func usesCompactFooter(innerWidth: CGFloat) -> Bool
	{
		innerWidth < metrics.compactWidthThreshold
	}

	/// The required constraints make the action group own each footer row's height.
	func footerHeight(
		compact: Bool,
		leadingHeight: CGFloat,
		preferenceHeight: CGFloat,
		actionHeight: CGFloat
	) -> CGFloat?
	{
		guard [leadingHeight, preferenceHeight, actionHeight]
			.allSatisfy(
				{
					$0.isFinite && $0 >= 0
				}
			),
			preferenceHeight <= actionHeight,
			compact || leadingHeight <= actionHeight
		else
		{
			return nil
		}
		return compact ? leadingHeight + metrics.compactRowSpacing + actionHeight : actionHeight
	}

	func desiredEditorHeight(
		contentHeight: CGFloat,
		viewportHeight: CGFloat
	) -> CGFloat
	{
		min(
			max(
				metrics.minimumHeight,
				viewportHeight * metrics.availableHeightFraction
			),
			max(
				metrics.minimumHeight,
				contentHeight
			)
		)
	}
}
