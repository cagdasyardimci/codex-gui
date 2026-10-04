import Foundation
import Testing

@testable import CodexGUI

struct GitDiffRowIndexTests
{
	@Test func variableHeightRowsIncludeSharedEdgesAndTrailingRows()
	{
		let rectangles = [
			CGRect(
				x: 0,
				y: 0,
				width: 100,
				height: 19
			),
			CGRect(
				x: 0,
				y: 19,
				width: 100,
				height: 57
			),
			CGRect(
				x: 0,
				y: 76,
				width: 100,
				height: 19
			),
		]
		let index = GitDiffRowIndex(rectangles: rectangles)
		#expect(index.candidates(
			from: 20,
			through: 75
		) == 1 ..< 2)
		#expect(index.candidates(
			from: 19,
			through: 19
		) == 0 ..< 2)
		#expect(index.candidates(
			from: 76,
			through: 76
		) == 1 ..< 3)
		#expect(index.candidates(
			from: 95,
			through: 96
		) == 2 ..< 3)
		#expect(index.candidates(
			from: 96,
			through: 100
		).isEmpty)
		#expect(index.candidates(
			from: -20,
			through: -1
		).isEmpty)
	}

	@Test func anEarlierOverlappingRowIsNotLostWhenLaterRowsAreShorter()
	{
		let rectangles = [
			CGRect(
				x: 0,
				y: 0,
				width: 100,
				height: 200
			),
			CGRect(
				x: 0,
				y: 19,
				width: 100,
				height: 19
			),
			CGRect(
				x: 0,
				y: 38,
				width: 100,
				height: 19
			),
		]
		let index = GitDiffRowIndex(rectangles: rectangles)
		let candidates = index.candidates(
			from: 100,
			through: 110
		)
		#expect(candidates.contains(0))
		let visible = candidates.filter
		{
			rectangles[$0].maxY >= 100 && rectangles[$0].minY <= 110
		}
		#expect(visible == [0])
	}

	@Test func dirtyQueriesMatchAllIntersectingRowsWithoutScanningTheWholeDocument()
	{
		var top: CGFloat = 0
		let rectangles = (0 ..< 10_000).map
		{
			row in
			let height = CGFloat(1 + row % 3) * 19
			defer
			{
				top += height
			}
			return CGRect(
				x: 0,
				y: top,
				width: 100,
				height: height
			)
		}
		let index = GitDiffRowIndex(rectangles: rectangles)
		for row in stride(
			from: 0,
			to: rectangles.count,
			by: 137
		)
		{
			let minimum = rectangles[row].minY + 1
			let maximum = minimum + 80
			let expected = rectangles.indices.filter
			{
				rectangles[$0].maxY >= minimum && rectangles[$0].minY <= maximum
			}
			let candidates = index.candidates(
				from: minimum,
				through: maximum
			)
			#expect(Array(candidates) == expected)
			#expect(candidates.count <= 6)
		}
	}

	@Test func unorderedGeometryFallsBackWithoutDroppingPaintableRows()
	{
		let index = GitDiffRowIndex(rectangles: [
			CGRect(
				x: 0,
				y: 50,
				width: 100,
				height: 19
			),
			CGRect(
				x: 0,
				y: 0,
				width: 100,
				height: 19
			),
		])
		#expect(index.candidates(
			from: 5,
			through: 10
		) == 0 ..< 2)
	}

	@Test func emptyAndInvalidDirtyQueriesReturnNoRows()
	{
		let empty = GitDiffRowIndex(rectangles: [])
		#expect(empty.candidates(
			from: 0,
			through: 20
		).isEmpty)
		let index = GitDiffRowIndex(rectangles: [CGRect(
			x: 0,
			y: 0,
			width: 1,
			height: 19
		)])
		#expect(index.candidates(
			from: 20,
			through: 10
		).isEmpty)
		#expect(index.candidates(
			from: .nan,
			through: 10
		).isEmpty)
	}
}
