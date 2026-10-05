import Foundation

/// Keeps the provisional title readable without interpreting the user's request.
enum ThreadTitleText
{
	static func placeholder(_ prompt: String) -> String
	{
		let text = normalized(prompt)
		return text.isEmpty ? "New chat" : text
	}

	static func normalized(_ text: String) -> String
	{
		let words = text.split(whereSeparator:
			{
				$0.isWhitespace
			})
		return String(words.joined(separator: " ").prefix(120))
	}
}
