import Foundation
import Testing

@testable import CodexGUI

struct MarkdownTableColumnWidthsTests
{
	@Test func interleavedStyledCellsAccumulateIndependently()
	{
		let runs = [run(
			"a",
			row: 0
		),
		run(
			String(
				repeating: "b",
				count: 35
			),
			row: 1
		),
		run(
			String(
				repeating: "c",
				count: 40
			),
			row: 0
		),
		run(
			"d",
			column: 1
		)]
		let widths = MarkdownTableColumnWidths.measure(runs)
		#expect(abs((widths[0]?[0] ?? 0) - 100 * 41.0 / 73) < 1e-10)
		#expect(abs((widths[0]?[1] ?? 0) - 100 * 32.0 / 73) < 1e-10)
	}

	@Test func saturationCountsCharactersAndPreservesOtherTables()
	{
		let family = "👨‍👩‍👧‍👦"
		let runs = [run(String(
			repeating: family,
			count: 33
		)),
		run(String(
			repeating: "é",
			count: 30
		)),
		run("x"),
		run(
			String(
				repeating: "later",
				count: 1_000
			),
			row: 1
		),
		run(
			String(
				repeating: "é",
				count: 40
			),
			column: 1
		),
		run(
			"",
			table: 1
		)]
		let widths = MarkdownTableColumnWidths.measure(runs)
		#expect(abs((widths[0]?[0] ?? 0) - 100 * 64.0 / 104) < 1e-10)
		#expect(abs((widths[0]?[1] ?? 0) - 100 * 40.0 / 104) < 1e-10)
		#expect(widths[1] == [50, 50])
		#expect(MarkdownTableColumnWidths.measure([]).isEmpty)
	}

	private func run(
		_ text: String,
		table: Int = 0,
		row: Int = 0,
		column: Int = 0
	) -> MarkdownTextRun
	{
		var style = MarkdownTextStyle()
		style.tableCell = MarkdownTableCell(
			tableID: table,
			row: row,
			column: column,
			columnCount: 2,
			columnSpan: 1,
			rowSpan: 1,
			alignment: .left,
			header: row == 0
		)
		return MarkdownTextRun(
			text: text,
			style: style
		)
	}
}
