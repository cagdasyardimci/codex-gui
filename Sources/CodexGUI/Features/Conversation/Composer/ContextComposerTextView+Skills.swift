import AppKit

@MainActor
extension ContextComposerTextView
{
	var skillMention: ComposerSkillAttachment?
	{
		guard let storage = textStorage
		else
		{
			return nil
		}
		var result: ComposerSkillAttachment?
		storage.enumerateAttribute(
			.attachment,
			in: NSRange(
				location: 0,
				length: storage.length
			)
		)
		{
			value, _, stop in
			if let skill = value as? ComposerSkillAttachment
			{
				result = skill
				stop.pointee = true
			}
		}
		return result
	}

	private var skillRanges: [NSRange]
	{
		guard let storage = textStorage
		else
		{
			return []
		}
		var ranges: [NSRange] = []
		storage.enumerateAttribute(
			.attachment,
			in: NSRange(
				location: 0,
				length: storage.length
			)
		)
		{
			value, range, _ in
			if value is ComposerSkillAttachment
			{
				ranges.append(range)
			}
		}
		return ranges
	}

	var draftText: String
	{
		let text = NSMutableString(string: string)
		for range in skillRanges.reversed()
		{
			text.deleteCharacters(in: range)
		}
		return text as String
	}

	func draftRange(for range: NSRange) -> NSRange
	{
		func offset(_ location: Int) -> Int
		{
			location - skillRanges.reduce(0)
			{
				$0 + max(
					0,
					min(
						$1.length,
						location - $1.location
					)
				)
			}
		}
		let start = offset(range.location)
		return NSRange(
			location: start,
			length: offset(NSMaxRange(range)) - start
		)
	}

	func displayRange(for range: NSRange) -> NSRange
	{
		func offset(_ location: Int) -> Int
		{
			var result = location
			for skill in skillRanges where skill.location <= result
			{
				result += skill.length
			}
			return result
		}
		let start = offset(range.location)
		return NSRange(
			location: start,
			length: offset(NSMaxRange(range)) - start
		)
	}

	func renderSkill(
		_ selection: ProjectSkillSelection?,
		title: String?
	)
	{
		guard !hasMarkedText(), let storage = textStorage
		else
		{
			return
		}
		if let current = skillMention, current.selection == selection,
			current.title == title
		{
			return
		}
		var attributes = typingAttributes
		attributes.removeValue(forKey: .attachment)
		let caret = draftRange(for: selectedRange())
		let previousLocation = skillRanges.first?.location ?? 0
		isUpdatingSkillMention = true
		defer
		{
			isUpdatingSkillMention = false
		}
		for range in skillRanges.reversed()
		{
			storage.deleteCharacters(in: range)
		}
		if let selection
		{
			let attachment = ComposerSkillAttachment(
				selection: selection,
				title: title ?? selection.name,
				appearance: effectiveAppearance
			)
			let text =
				NSMutableAttributedString(
					attributedString: NSAttributedString(attachment: attachment)
				)
			text.addAttributes(
				attributes,
				range: NSRange(
					location: 0,
					length: text.length
				)
			)
			storage.insert(
				text,
				at: min(
					previousLocation,
					storage.length
				)
			)
		}
		let range = displayRange(for: caret)
		setSelectedRange(NSRange(
			location: min(
				range.location,
				storage.length
			),
			length: min(
				range.length,
				max(
					0,
					storage.length - range.location
				)
			)
		))
		typingAttributes = attributes
		needsDisplay = true
	}
}
