import Foundation

struct MarkdownFileReference
{
	let path: String
	let line: Int?

	init?(_ destination: String)
	{
		guard destination.hasPrefix("/") || destination.hasPrefix("file://")
		else
		{
			return nil
		}
		var value = destination
		var line: Int?
		if let match = value.range(
			of: #"(?::|#L)([0-9]+)$"#,
			options: .regularExpression
		)
		{
			let suffix = value[match]
			let digits = suffix.drop(while:
				{
					!$0.isNumber
				})
			if let number = Int(digits), number > 0
			{
				line = number
				value.removeSubrange(match)
			}
		}
		if value.hasPrefix("file://")
		{
			guard let url = URL(string: value), url.isFileURL
			else
			{
				return nil
			}
			path = url.path
		}
		else
		{
			path = value.removingPercentEncoding ?? value
		}
		self.line = line
	}
}
