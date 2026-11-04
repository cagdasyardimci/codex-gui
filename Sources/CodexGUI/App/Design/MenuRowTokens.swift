import AppKit

extension LayoutTokens
{
	enum MenuRow
	{
		static let horizontalInset: CGFloat = 8
		static let verticalInset: CGFloat = 5
		static let minimumHeight: CGFloat = 26
		static let iconSize: CGFloat = 16
		static let iconSpacing: CGFloat = 6
		static var titleLineHeight: CGFloat
		{
			TypographyTokens.MenuRow.title.lineHeight!
		}
		static var subtitleLineHeight: CGFloat
		{
			TypographyTokens.MenuRow.subtitle.lineHeight!
		}
		static var height: CGFloat
		{
			max(
				minimumHeight,
				titleLineHeight + 2 * verticalInset
			)
		}
		static var detailedHeight: CGFloat
		{
			height + subtitleLineHeight
		}
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
		static let title = TypographyTokens.Text.menu
		static let subtitle = TypographyTokens.Text.menuSupport
	}
}

extension ShapeTokens
{
	enum SearchSuggestions
	{
		static let cornerRadius: CGFloat = 22
	}
}
