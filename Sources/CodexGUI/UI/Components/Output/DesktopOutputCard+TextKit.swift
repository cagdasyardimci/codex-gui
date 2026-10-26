import AppKit

extension DesktopOutputCard
{
	/// TextKit keeps native selection/layout while using output-card chrome and measurement roles.
	@MainActor
	enum TextKitPresentation
	{
		case transcriptCode, fileCode

		var contentInset: CGFloat
		{
			self == .transcriptCode ? 18 : 0
		}
		var headerHeight: CGFloat
		{
			self == .transcriptCode ? 44 : 20.8
		}
		var bottomPadding: CGFloat
		{
			self == .transcriptCode ? 16 : 4
		}
		var blockSpacing: CGFloat
		{
			self == .transcriptCode ? 16 : 20.8
		}
		var cornerRadius: CGFloat
		{
			self == .transcriptCode ? 16 : 8
		}
	}

	static func drawTextKitCard(
		in card: NSRect,
		language: String?,
		presentation: TextKitPresentation
	)
	{
		let path = NSBezierPath(
			roundedRect: card,
			xRadius: presentation.cornerRadius,
			yRadius: presentation.cornerRadius
		)
		if presentation == .fileCode
		{
			NSColor.labelColor.withAlphaComponent(0.00549).setFill()
			path.fill()
		}
		else
		{
			AppKitColorTokens.elevated.setFill()
			path.fill()
			AppKitColorTokens.border.setStroke()
			path.lineWidth = 1
			path.stroke()
		}
		guard let language, !language.isEmpty
		else
		{
			return
		}
		if presentation == .fileCode
		{
			let attributes: [NSAttributedString.Key: Any] = [
				.font: NSFont.systemFont(ofSize: 12),
				.foregroundColor: NSColor.secondaryLabelColor,
			]
			let title = language.lowercased() as NSString
			let width = min(
				card.width,
				title.size(withAttributes: attributes).width
			)
			title.draw(
				in: NSRect(
					x: card.maxX - width,
					y: card.minY,
					width: width,
					height: 17
				),
				withAttributes: attributes
			)
			return
		}
		let attributes: [NSAttributedString.Key: Any] = [
			.font: NSFont.systemFont(
				ofSize: 12,
				weight: .medium
			),
			.foregroundColor: NSColor.labelColor,
		]
		("‹/›" as NSString).draw(
			at: NSPoint(
				x: card.minX + presentation.contentInset,
				y: card.minY + 14
			),
			withAttributes: attributes
		)
		let titleRect = NSRect(
			x: card.minX + presentation.contentInset + 26,
			y: card.minY + 14,
			width: max(
				1,
				card.width - presentation.contentInset - 70
			),
			height: 16
		)
		(languageTitle(language) as NSString).draw(
			in: titleRect,
			withAttributes: attributes
		)
	}

	private static func languageTitle(_ language: String) -> String
	{
		let titles = [
			"python": "Python",
			"swift": "Swift",
			"javascript": "JavaScript",
			"typescript": "TypeScript",
			"json": "JSON",
			"html": "HTML",
			"css": "CSS",
			"bash": "Bash",
			"mermaid": "Mermaid",
			"text": "Text",
		]
		return titles[language.lowercased()] ?? language
	}
}
