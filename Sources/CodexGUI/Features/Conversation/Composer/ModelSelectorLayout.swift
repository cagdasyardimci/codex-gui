import Foundation

/// Resolves model-control requests and drawing geometry from the same immutable inputs.
struct ModelSelectorLayout: Sendable
{
	let metrics: LayoutTokens.ModelSelector

	init(metrics: LayoutTokens.ModelSelector = LayoutTokens.modelSelector)
	{
		self.metrics = metrics
	}

	func fits(controlHeight: CGFloat) -> Bool
	{
		max(
			metrics.boltSize.height,
			metrics.chevronSize.height
		) <= controlHeight
	}

	func requestedWidth(
		titleWidth: CGFloat,
		displaysBolt: Bool,
		picker: Bool
	) -> CGFloat
	{
		let natural = ceil(titleWidth) + metrics.totalHorizontalAllowance
			+ metrics.trailingReservedWidth + (displaysBolt ? metrics.boltReservedWidth : 0)
		return min(
			metrics.maximumWidth,
			max(
				picker ? metrics.pickerMinimumWidth : 1,
				natural
			)
		)
	}

	struct Content: Sendable
	{
		let boltRect: CGRect
		let textRect: CGRect
		let chevronRect: CGRect
	}

	func content(
		in bounds: CGRect,
		titleSize: CGSize,
		displaysBolt: Bool
	) -> Content
	{
		let leading = displaysBolt ? metrics.boltReservedWidth : 0
		let available = max(
			0,
			bounds.width - metrics.totalHorizontalAllowance
		)
		let width = min(
			available,
			titleSize.width + leading + metrics.trailingReservedWidth
		)
		let textWidth = max(
			0,
			width - leading - metrics.trailingReservedWidth
		)
		let origin = bounds.midX - width / 2
		let text = CGRect(
			x: origin + leading,
			y: bounds.midY - titleSize.height / 2,
			width: textWidth,
			height: titleSize.height
		)
		return Content(
			boltRect: CGRect(
				x: origin,
				y: bounds.midY - metrics.boltSize.height / 2,
				width: metrics.boltSize.width,
				height: metrics.boltSize.height
			),
			textRect: text,
			chevronRect: CGRect(
				x: text.maxX + metrics.titleToChevronSpacing,
				y: bounds.midY - metrics.chevronSize.height / 2,
				width: metrics.chevronSize.width,
				height: metrics.chevronSize.height
			)
		)
	}
}
