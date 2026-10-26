import AppKit

/// Additions and deletions share complete numeric, color, spacing and accessibility presentation.
@MainActor
final class DesktopDiffStats: NSStackView
{
	struct Counts: Equatable
	{
		let additions: Int
		let deletions: Int
	}

	enum Presentation
	{
		case summary, toolbar, fileHeader, fileTree, resource, transcript, turnSummary
	}

	let additionsLabel = NSTextField(labelWithString: "")
	let deletionsLabel = NSTextField(labelWithString: "")
	private let presentation: Presentation
	private var valueLabel: NSTextField?

	init(
		counts: Counts?,
		presentation: Presentation
	)
	{
		self.presentation = presentation
		super.init(frame: .zero)
		orientation = .horizontal
		alignment = .centerY
		spacing = presentation == .summary ? 4 : (presentation == .fileHeader ? 12 : 6)
		if presentation == .resource || presentation == .transcript
		{
			let value: NSTextField = presentation == .transcript
				? DesktopDiffStatsTextField(labelWithString: "") : NSTextField(labelWithString: "")
			valueLabel = value
			addArrangedSubview(value)
		}
		else
		{
			additionsLabel.textColor = .systemGreen
			deletionsLabel.textColor = .systemRed
			for label in [additionsLabel, deletionsLabel]
			{
				if presentation == .summary
				{
					label.font = AppKitFontResolver.font(TypographyTokens.Summary.body)
					label.lineBreakMode = .byTruncatingTail
					label.maximumNumberOfLines = 1
					label.setContentCompressionResistancePriority(
						.defaultLow,
						for: .horizontal
					)
				}
				else if presentation == .toolbar
				{
					label.font = .systemFont(ofSize: 13)
				}
				addArrangedSubview(label)
			}
		}
		update(counts)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func update(_ counts: Counts?)
	{
		if let valueLabel
		{
			Self.apply(
				counts ?? Counts(
					additions: 0,
					deletions: 0
				),
				to: valueLabel,
				presentation: presentation
			)
			return
		}
		guard let counts
		else
		{
			additionsLabel.stringValue = "—"
			deletionsLabel.stringValue = "—"
			return
		}
		let grouped = presentation == .summary || presentation == .toolbar
		additionsLabel.stringValue = "+" + Self.number(
			counts.additions,
			grouped: grouped
		)
		deletionsLabel.stringValue = "-" + Self.number(
			counts.deletions,
			grouped: grouped
		)
		if presentation == .summary
		{
			additionsLabel.setAccessibilityLabel("\(counts.additions) additions")
			deletionsLabel.setAccessibilityLabel("\(counts.deletions) deletions")
		}
		if presentation == .fileTree
		{
			additionsLabel.isHidden = counts.additions <= 0
			deletionsLabel.isHidden = counts.deletions <= 0
		}
	}

	/// TextKit/native label hosts keep their renderer while consuming the same stats presentation.
	static func apply(
		_ counts: Counts,
		to label: NSTextField,
		presentation: Presentation
	)
	{
		label.font = .systemFont(ofSize: 13)
		label.attributedStringValue = attributedValue(
			counts,
			presentation: presentation
		)
	}

	static func attributedValue(
		_ counts: Counts,
		presentation: Presentation
	) -> NSAttributedString
	{
		let grouped = presentation == .summary || presentation == .toolbar
		let value = NSMutableAttributedString(
			string: (presentation == .turnSummary ? " +" : "+") + number(
				counts.additions,
				grouped: grouped
			),
			attributes: attributes(
				color: .systemGreen,
				presentation: presentation
			)
		)
		value.append(NSAttributedString(
			string: " -" + number(
				counts.deletions,
				grouped: grouped
			),
			attributes: attributes(
				color: .systemRed,
				presentation: presentation
			)
		))
		return value
	}

	private static func attributes(
		color: NSColor,
		presentation: Presentation
	)
		-> [NSAttributedString.Key: Any]
	{
		var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: color]
		if presentation == .turnSummary
		{
			attributes[.font] = NSFont.systemFont(ofSize: 13)
		}
		return attributes
	}

	private static func number(
		_ value: Int,
		grouped: Bool
	) -> String
	{
		guard grouped
		else
		{
			return String(value)
		}
		let formatter = NumberFormatter()
		formatter.numberStyle = .decimal
		formatter.locale = Locale(identifier: "en_US")
		return formatter.string(from: NSNumber(value: value)) ?? String(value)
	}
}

@MainActor
private final class DesktopDiffStatsTextField: NSTextField
{
	override func draw(_ dirtyRect: NSRect)
	{
		MarkdownTextDrawing.withAntialiasing
		{
			super.draw(dirtyRect)
		}
	}
}
