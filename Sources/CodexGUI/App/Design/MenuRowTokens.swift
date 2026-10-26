import AppKit

extension LayoutTokens
{
	enum MenuRow
	{
		static let horizontalInset: CGFloat = 8
		static let verticalInset: CGFloat = 5
		static let iconSize: CGFloat = 16
		static let iconSpacing: CGFloat = 6
		static let titleLineHeight: CGFloat = 18.5703125
		static let subtitleLineHeight: CGFloat = 14
		static let height = titleLineHeight + 2 * verticalInset
		static let detailedHeight = height + subtitleLineHeight
	}
	/// Inline search suggestions retain their native table line box and bounded viewport.
	enum SearchSuggestions
	{
		static let rowHeight: CGFloat = 28
		static let contentInset: CGFloat = 4
		static let preferredWidth: CGFloat = 720
		static let maximumVisibleRows = 11

		static func preferredHeight(rowCount: Int) -> CGFloat
		{
			CGFloat(min(
				maximumVisibleRows,
				max(
					1,
					rowCount
				)
			)) * rowHeight + 2 * contentInset
		}
	}

}

extension TypographyTokens
{
	enum MenuRow
	{
		static let title = Role(
			size: 13,
			selection: .interface(weight: 430),
			lineHeight: LayoutTokens.MenuRow.titleLineHeight
		)
		static let subtitle = Role(
			size: 12,
			selection: .interface(weight: 430),
			lineHeight: LayoutTokens.MenuRow.subtitleLineHeight
		)
	}
}

extension ShapeTokens
{
	enum SearchSuggestions
	{
		static let cornerRadius: CGFloat = 22
	}
}
