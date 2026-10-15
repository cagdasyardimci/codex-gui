import AppKit

/// Adds the same web-link decoration to compact turn cards without changing their plain text cache.
@MainActor
enum TurnSummaryLinkPresentation
{
	static func styledTitle(
		_ source: String,
		attributes: [NSAttributedString.Key: Any]
	) -> NSAttributedString
	{
		let parsed = MarkdownContentParser.parse(
			source,
			markdown: true
		)
		let presentation = MarkdownPlainTextRenderer.renderWithLinks(parsed)
		return styled(
			presentation.text,
			explicitLinks: presentation.links,
			attributes: attributes
		)
	}

	static func styled(
		_ text: String,
		source: String?,
		attributes: [NSAttributedString.Key: Any]
	) -> NSAttributedString
	{
		let explicitLinks: [MarkdownPlainTextLink] = source.flatMap
		{
			let parsed = MarkdownContentParser.parse(
				$0,
				markdown: true
			)
			let presentation = MarkdownPlainTextRenderer.renderWithLinks(parsed)
			return presentation.text == text ? presentation.links : nil
		} ?? []
		return styled(
			text,
			explicitLinks: explicitLinks,
			attributes: attributes
		)
	}

	private static func styled(
		_ text: String,
		explicitLinks: [MarkdownPlainTextLink],
		attributes: [NSAttributedString.Key: Any]
	) -> NSAttributedString
	{
		let result = NSMutableAttributedString(
			string: text,
			attributes: attributes
		)
		let visibleLinks = WebLinkDetector.links(in: text).filter
		{
			visible in
			!explicitLinks.contains
			{
				NSIntersectionRange(
					$0.range,
					visible.range
				).length > 0
			}
		}
		let links = (explicitLinks + visibleLinks).sorted
		{
			$0.range.location < $1.range.location
		}
		for link in links
		{
			guard let url = WebLinkDetector.webURL(link.destination),
					NSMaxRange(link.range) <= result.length
			else
			{
				continue
			}
			result.addAttributes(
				[
					.link: url,
					.foregroundColor: MarkdownAttributedStringRenderer.linkColor,
					.underlineStyle: 0,
				],
				range: link.range
			)
		}
		for link in links.reversed()
		{
			guard let url = WebLinkDetector.webURL(link.destination),
					link.range.location <= result.length
			else
			{
				continue
			}
			let icon = NSMutableAttributedString(attachment: WebLinkFaviconAttachment(url: url))
			icon.addAttributes(
				[
					.link: url,
					.foregroundColor: MarkdownAttributedStringRenderer.linkColor,
				],
				range: NSRange(
					location: 0,
					length: icon.length
				)
			)
			result.insert(
				icon,
				at: link.range.location
			)
		}
		return result
	}

	static func compactLines(_ text: NSAttributedString) -> NSAttributedString
	{
		let result = NSMutableAttributedString(string: "")
		var position = 0
		for line in text.string.components(separatedBy: "\n")
		{
			let length = line.utf16.count
			if !line.trimmingCharacters(in: .whitespaces).isEmpty
			{
				if result.length > 0
				{
					result.append(NSAttributedString(string: "\n"))
				}
				result.append(text.attributedSubstring(from: NSRange(
					location: position,
					length: length
				)))
			}
			position += length + 1
		}
		return result
	}

}
