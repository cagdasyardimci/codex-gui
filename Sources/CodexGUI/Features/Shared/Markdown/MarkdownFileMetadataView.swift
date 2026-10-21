import AppKit

/// Native frontmatter grid, reusable as a fixed Files header or an inline rich-preview panel.
@MainActor
final class MarkdownFileMetadataView: NSView
{
	let entries: [MarkdownFileMetadata.Entry]
	private let heading = NSTextField(labelWithString: "Metadata")
	private var keys: [NSTextField] = []
	private var values: [[NSTextField]] = []
	private var measuredWidth: CGFloat = 0
	private static let inset: CGFloat = 12
	private static let rowGap: CGFloat = 6
	private static let font = NSFont.monospacedSystemFont(
		ofSize: 12,
		weight: .regular
	)

	init(entries: [MarkdownFileMetadata.Entry])
	{
		self.entries = entries
		super.init(frame: .zero)
		wantsLayer = true
		layer?.cornerRadius = 8
		layer?.borderWidth = 1
		setAccessibilityLabel("Metadata")
		heading.font = .systemFont(ofSize: 12)
		heading.textColor = AppKitColorTokens.secondaryText
		addSubview(heading)
		for entry in entries
		{
			let key = label(entry.key)
			key.textColor = AppKitColorTokens.secondaryText
			keys.append(key)
			addSubview(key)
			let fields = entry.values.map
			{
				value in
				let field = label(value)
				if entry.isSequence
				{
					field.wantsLayer = true
					field.layer?.cornerRadius = 7
					field.alignment = .center
				}
				addSubview(field)
				return field
			}
			values.append(fields)
		}
		refreshAppearance()
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override var isFlipped: Bool
	{
		true
	}

	override var intrinsicContentSize: NSSize
	{
		NSSize(
			width: NSView.noIntrinsicMetric,
			height: height(forWidth: max(
				1,
				bounds.width
			))
		)
	}

	func height(forWidth width: CGFloat) -> CGFloat
	{
		geometry(width: width).height
	}

	override func layout()
	{
		super.layout()
		let layout = geometry(width: bounds.width)
		heading.frame = NSRect(
			x: 12,
			y: 9,
			width: max(
				1,
				bounds.width - 24
			),
			height: 17
		)
		for index in entries.indices
		{
			keys[index].frame = layout.keys[index]
			for valueIndex in values[index].indices
			{
				values[index][valueIndex].frame = layout.values[index][valueIndex]
			}
		}
		if measuredWidth != bounds.width
		{
			measuredWidth = bounds.width
			invalidateIntrinsicContentSize()
		}
	}

	private func label(_ text: String) -> NSTextField
	{
		let field = NSTextField(wrappingLabelWithString: text)
		field.font = Self.font
		field.textColor = AppKitColorTokens.primaryText
		field.isSelectable = true
		field.lineBreakMode = .byWordWrapping
		field.maximumNumberOfLines = 0
		return field
	}

	private struct Geometry
	{
		let height: CGFloat
		let keys: [NSRect]
		let values: [[NSRect]]
	}

	private func geometry(width: CGFloat) -> Geometry
	{
		let innerWidth = max(
			1,
			width - Self.inset * 2
		)
		let keyWidth = min(
			140,
			innerWidth * 0.3
		)
		let valueX = Self.inset + keyWidth
		let valueWidth = max(
			1,
			innerWidth - keyWidth
		)
		var y: CGFloat = 32
		var keyFrames: [NSRect] = []
		var valueFrames: [[NSRect]] = []
		for entry in entries
		{
			var frames: [NSRect] = []
			var rowHeight: CGFloat = 16
			if entry.isSequence
			{
				var x: CGFloat = 0
				var chipY = y
				var lineHeight: CGFloat = 20
				for value in entry.values
				{
					let size = (value as NSString).size(withAttributes: [.font: Self.font])
					let chipWidth = min(
						valueWidth,
						ceil(size.width) + 12
					)
					if x > 0, x + chipWidth > valueWidth
					{
						x = 0
						chipY += lineHeight + 4
						lineHeight = 20
					}
					let chipHeight = max(
						20,
						textHeight(
							value,
							width: max(
								1,
								chipWidth - 8
							)
						) + 4
					)
					lineHeight = max(
						lineHeight,
						chipHeight
					)
					frames.append(NSRect(
						x: valueX + x,
						y: chipY - 2,
						width: chipWidth,
						height: chipHeight
					))
					x += chipWidth + 4
					rowHeight = max(
						rowHeight,
						chipY - y + chipHeight - 2
					)
				}
			}
			else
			{
				rowHeight = textHeight(
					entry.values.first ?? "",
					width: valueWidth
				)
				frames.append(NSRect(
					x: valueX,
					y: y,
					width: valueWidth,
					height: rowHeight
				))
			}
			let keyHeight = textHeight(
				entry.key,
				width: max(
					1,
					keyWidth - 8
				)
			)
			keyFrames.append(NSRect(
				x: Self.inset,
				y: y,
				width: max(
					1,
					keyWidth - 8
				),
				height: keyHeight
			))
			valueFrames.append(frames)
			y += max(
				rowHeight,
				keyHeight
			) + Self.rowGap
		}
		return Geometry(
			height: y + 4,
			keys: keyFrames,
			values: valueFrames
		)
	}

	private func textHeight(
		_ text: String,
		width: CGFloat
	) -> CGFloat
	{
		max(
			16,
			ceil((text as NSString).boundingRect(
				with: NSSize(
					width: width,
					height: .greatestFiniteMagnitude
				),
				options: [.usesLineFragmentOrigin, .usesFontLeading],
				attributes: [.font: Self.font]
			).height)
		)
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		refreshAppearance()
	}

	private func refreshAppearance()
	{
		effectiveAppearance.performAsCurrentDrawingAppearance
		{
			layer?.backgroundColor = AppKitColorTokens.chrome.cgColor
			layer?.borderColor = AppKitColorTokens.border.cgColor
			for index in entries.indices where entries[index].isSequence
			{
				for field in values[index]
				{
					field.layer?.backgroundColor = AppKitColorTokens.selection.cgColor
				}
			}
		}
	}
}
