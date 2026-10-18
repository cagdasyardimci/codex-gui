import Foundation

/// One exact source identity for preparation reuse and the bounded prepared-content cache.
struct ConversationContentKey: Hashable, Sendable
{
	let body: String
	let markdown: Bool
	let preserveSoftBreaks: Bool

	init(
		body: String,
		markdown: Bool,
		preserveSoftBreaks: Bool = false
	)
	{
		self.body = body
		self.markdown = markdown
		self.preserveSoftBreaks = preserveSoftBreaks
	}

	static func == (lhs: Self, rhs: Self) -> Bool
	{
		lhs.markdown == rhs.markdown && lhs.preserveSoftBreaks == rhs.preserveSoftBreaks
			&& lhs.body.utf8.elementsEqual(rhs.body.utf8)
	}

	func hash(into hasher: inout Hasher)
	{
		// Canonically equivalent bodies may share a hash; equality still checks their exact bytes.
		hasher.combine(body)
		hasher.combine(markdown)
		hasher.combine(preserveSoftBreaks)
	}

	static func make(
		for entry: ConversationEntry,
		expanded: Bool
	) -> Self?
	{
		// Commands and images use activity rows, without prepared message text.
		guard entry.activity == nil
		else
		{
			return nil
		}
		let collapsed = entry.isExpandable && !expanded
		let body = collapsed ? collapsedPreview(of: entry.body) : entry.body
		return Self(
			body: body,
			markdown: entry.kind == .agent || entry.kind == .user,
			preserveSoftBreaks: entry.kind == .user
		)
	}

	static func collapsedPreview(of body: String) -> String
	{
		var preview = ""
		var separators = 0
		for scalar in body.unicodeScalars
		{
			if CharacterSet.newlines.contains(scalar)
			{
				if separators == 1
				{
					return preview
				}
				separators += 1
				preview += "\n"
			}
			else
			{
				preview.unicodeScalars.append(scalar)
			}
		}
		return preview
	}
}
