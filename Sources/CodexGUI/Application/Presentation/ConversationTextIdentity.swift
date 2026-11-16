import Foundation

/// Exact source equality without walking long transcript bodies through Swift iterators.
enum ConversationTextIdentity
{
	static func matches(
		_ first: String,
		_ second: String
	) -> Bool
	{
		var first = first
		var second = second
		return first.withUTF8
		{
			left in
			second.withUTF8
			{
				right in
				guard left.count == right.count
				else
				{
					return false
				}
				guard let leftBase = left.baseAddress, let rightBase = right.baseAddress
				else
				{
					return left.isEmpty
				}
				return leftBase == rightBase || memcmp(
					leftBase,
					rightBase,
					left.count
				) == 0
			}
		}
	}
}
