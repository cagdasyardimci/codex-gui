import Foundation

enum NavigationSidebarLayout
{
	private static let metrics: LayoutTokens.Sidebar =
	{
		let metrics = LayoutTokens.sidebar
		precondition(
			isValid(metrics),
			"Invalid sidebar metrics"
		)
		return metrics
	}()
	static var rowHeight: CGFloat
	{
		metrics.rowHeight
	}
	static var rowSpacing: CGFloat
	{
		metrics.rowSpacing
	}
	static var cellInset: CGFloat
	{
		metrics.cellInset
	}
	static var iconSize: CGFloat
	{
		metrics.iconSize
	}
	static var iconTextSpacing: CGFloat
	{
		metrics.iconTextSpacing
	}
	static var projectTitleInset: CGFloat
	{
		metrics.projectTitleInset
	}
	static var sectionSpacing: CGFloat
	{
		metrics.sectionSpacing
	}
	static var sectionContentSpacing: CGFloat
	{
		metrics.sectionContentSpacing
	}

	static func isValid(_ metrics: LayoutTokens.Sidebar) -> Bool
	{
		metrics.isValid && metrics.rowHeight >= LayoutTokens.Sidebar.headingActionSize
			&& metrics.iconSize <= metrics.rowHeight
			&& metrics.rowSpacing <= min(
				metrics.sectionSpacing,
				metrics.sectionContentSpacing
			)
	}

	static func sectionTopInset(
		at row: Int,
		metrics: LayoutTokens.Sidebar = LayoutTokens.sidebar
	) -> CGFloat
	{
		precondition(
			isValid(metrics),
			"Invalid sidebar layout metrics"
		)
		return row == 0 ? 0 : metrics.sectionSpacing - metrics.rowSpacing
	}

	static func sectionRowHeight(
		at row: Int,
		metrics: LayoutTokens.Sidebar = LayoutTokens.sidebar
	) -> CGFloat
	{
		sectionTopInset(
			at: row,
			metrics: metrics
		) + metrics.rowHeight + metrics.sectionContentSpacing - metrics.rowSpacing
	}
}
