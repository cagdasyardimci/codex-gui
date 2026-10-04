import Foundation

/// Finds candidate rows by vertical bounds, including rows that overlap their successors.
struct GitDiffRowIndex
{
	private let starts: [CGFloat]
	private let maximumBottoms: [CGFloat]
	private let hasOrderedStarts: Bool

	init(rectangles: [CGRect])
	{
		var starts: [CGFloat] = []
		var bottoms: [CGFloat] = []
		var maximumBottom = -CGFloat.infinity
		var ordered = true
		for rectangle in rectangles
		{
			if !rectangle.minY.isFinite || !rectangle.maxY.isFinite
				|| starts.last.map(
					{
						$0 > rectangle.minY
					}
				) == true
			{
				ordered = false
			}
			starts.append(rectangle.minY)
			maximumBottom = max(
				maximumBottom,
				rectangle.maxY
			)
			bottoms.append(maximumBottom)
		}
		self.starts = starts
		maximumBottoms = bottoms
		hasOrderedStarts = ordered
	}

	func candidates(
		from minimumY: CGFloat,
		through maximumY: CGFloat
	) -> Range<Int>
	{
		guard minimumY.isFinite, maximumY.isFinite, minimumY <= maximumY
		else
		{
			return 0 ..< 0
		}
		guard hasOrderedStarts
		else
		{
			return starts.indices
		}
		let first = firstIndex(
			in: maximumBottoms,
			at: minimumY,
			includingBoundary: true
		)
		let end = firstIndex(
			in: starts,
			at: maximumY,
			includingBoundary: false
		)
		return first ..< max(
			first,
			end
		)
	}

	private func firstIndex(
		in values: [CGFloat],
		at boundary: CGFloat,
		includingBoundary: Bool
	) -> Int
	{
		var lower = 0
		var upper = values.count
		while lower < upper
		{
			let middle = lower + (upper - lower) / 2
			let isBeforeBoundary = includingBoundary
				? values[middle] < boundary : values[middle] <= boundary
			if isBeforeBoundary
			{
				lower = middle + 1
			}
			else
			{
				upper = middle
			}
		}
		return lower
	}
}
