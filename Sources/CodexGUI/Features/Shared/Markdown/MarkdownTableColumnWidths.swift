import Foundation

/// Pure table geometry shared by rendering and tests; styled runs may interleave cells.
enum MarkdownTableColumnWidths
{
	static func measure(_ runs: [MarkdownTextRun]) -> [Int: [CGFloat]]
	{
		var cellLengths: [MarkdownTableCell.Identity: Int] = [:]
		var widths: [Int: [CGFloat]] = [:]
		for run in runs
		{
			guard let cell = run.style.tableCell
			else
			{
				continue
			}
			if widths[cell.tableID] == nil
			{
				widths[cell.tableID] = Array(
					repeating: 32,
					count: cell.columnCount
				)
			}
			// A saturated column cannot grow with later rows or styled fragments.
			let current = widths[cell.tableID]![cell.column]
			guard current < 64
			else
			{
				continue
			}
			let key = cell.identity
			let previous = cellLengths[key, default: 0]
			let length = previous + run.text.prefix(64 - previous).count
			if length == 64
			{
				cellLengths.removeValue(forKey: key)
			}
			else
			{
				cellLengths[key] = length
			}
			widths[cell.tableID]![cell.column] = max(
				current,
				CGFloat(length)
			)
		}
		return widths.mapValues
		{
			columns in
			let total = columns.reduce(
				0,
				+
			)
			return columns.map
			{
				100 * $0 / max(
					1,
					total
				)
			}
		}
	}
}
