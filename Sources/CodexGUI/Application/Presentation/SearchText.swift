import Foundation

struct SearchText: Equatable
{
	let terms: [String]

	func matches(_ query: String) -> Bool
	{
		let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
		return query.isEmpty || terms.contains
		{
			$0.localizedCaseInsensitiveContains(query)
		}
	}
}
