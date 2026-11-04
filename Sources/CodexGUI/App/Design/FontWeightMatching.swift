import Foundation

/// CSS face matching keeps 400...500 requests on a regular-only family before trying bold.
enum FontWeightMatching
{
	static func match(
		_ requested: Int,
		available: [Int]
	) -> Int?
	{
		let weights = Set(available).sorted()
		if (400 ... 500).contains(requested)
		{
			return weights.first
			{
				$0 >= requested && $0 <= 500
			}
			?? weights.last
			{
				$0 < requested
			}
			?? weights.first
			{
				$0 > 500
			}
		}
		if requested < 400
		{
			return weights.last
			{
				$0 <= requested
			} ?? weights.first
			{
				$0 > requested
			}
		}
		return weights.first
		{
			$0 >= requested
		} ?? weights.last
		{
			$0 < requested
		}
	}
}
