import Foundation

/// One web-link rule for Markdown prose and compact turn previews.
enum WebLinkDetector
{
	private static let detector = try? NSDataDetector(
		types: NSTextCheckingResult.CheckingType.link.rawValue
	)

	static func webURL(_ value: String?) -> URL?
	{
		guard let value, let url = URL(string: value),
				let scheme = url.scheme?.lowercased(),
				["http", "https"].contains(scheme),
				url.host != nil
		else
		{
			return nil
		}
		return url
	}

	static func links(in text: String) -> [MarkdownPlainTextLink]
	{
		guard let detector
		else
		{
			return []
		}
		return detector.matches(
			in: text,
			range: NSRange(
				location: 0,
				length: text.utf16.count
			)
		).compactMap
		{
			match in
			guard let url = webURL(match.url?.absoluteString)
			else
			{
				return nil
			}
			return MarkdownPlainTextLink(
				range: match.range,
				destination: url.absoluteString
			)
		}
	}
}
