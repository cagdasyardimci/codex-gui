import Foundation

/// Shares preview text preparation while callers retain their own storage limits.
enum ConversationTurnPreviewText
{
	private static let maximumSourceCharacters = 400
	private static let maximumReplyCharacters = 800

	static func sourcePrefix(_ text: String) -> String
	{
		String(text.prefix(maximumSourceCharacters))
	}

	static func title(
		_ text: String,
		maximumLength: Int
	) -> String
	{
		let normalized = sourcePrefix(text)
			.split(whereSeparator: \.isWhitespace).joined(separator: " ")
		return String(normalized.prefix(maximumLength))
	}

	static func reply(_ renderedText: String) -> String
	{
		String(renderedText.prefix(maximumReplyCharacters))
	}
}
