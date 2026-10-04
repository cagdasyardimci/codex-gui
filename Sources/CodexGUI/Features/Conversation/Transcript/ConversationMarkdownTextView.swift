import AppKit

/// Matches the reference's grayscale antialiasing while retaining native font metrics.
@MainActor
enum ConversationTextDrawing
{
	static func withAntialiasing(_ draw: () -> Void)
	{
		guard let context = NSGraphicsContext.current?.cgContext
		else
		{
			draw()
			return
		}
		context.saveGState()
		defer
		{
			context.restoreGState()
		}
		context.setShouldSmoothFonts(false)
		draw()
	}
}

/// Native rich content keeps its original source available to selection copy and accessible help.
@MainActor
final class ConversationMarkdownTextView: NSTextView
{
	private var updatingFrameSize = false

	override func draw(_ dirtyRect: NSRect)
	{
		ConversationTextDrawing.withAntialiasing
		{
			super.draw(dirtyRect)
		}
	}

	override func setFrameSize(_ newSize: NSSize)
	{
		let wasUpdatingFrameSize = updatingFrameSize
		updatingFrameSize = true
		defer
		{
			updatingFrameSize = wasUpdatingFrameSize
		}
		super.setFrameSize(newSize)
	}

	override func scrollToVisible(_ rect: NSRect) -> Bool
	{
		// NSTextView scrolls its caret during frame changes. The transcript controller
		// preserves the reading anchor across those changes instead.
		guard !updatingFrameSize
		else
		{
			return false
		}
		return super.scrollToVisible(rect)
	}

	override func writeSelection(
		to pasteboard: NSPasteboard,
		types: [NSPasteboard.PasteboardType]
	) -> Bool
	{
		let wroteNativeFormats = super.writeSelection(
			to: pasteboard,
			types: types
		)
		var plainTextTypes = Set(types.filter(Self.isPlainText))
		if types.isEmpty || !plainTextTypes.isEmpty
		{
			plainTextTypes.formUnion((pasteboard.types ?? []).filter(Self.isPlainText))
		}
		if types.isEmpty
		{
			plainTextTypes.insert(.string)
		}
		// The native multi-type writer can replace the string produced by the single-type hook.
		var wroteSourceText = false
		for type in plainTextTypes
		{
			let wroteType = writeSelection(
				to: pasteboard,
				type: type
			)
			wroteSourceText = wroteType || wroteSourceText
		}
		return wroteNativeFormats || wroteSourceText
	}

	override func writeSelection(
		to pasteboard: NSPasteboard,
		type: NSPasteboard.PasteboardType
	) -> Bool
	{
		guard Self.isPlainText(type), let storage = textStorage
		else
		{
			return super.writeSelection(
				to: pasteboard,
				type: type
			)
		}
		let selections = selectedRanges.map(\.rangeValue)
		guard selections.contains(where:
			{
				$0.length > 0
			})
		else
		{
			return false
		}
		let text = selections.map
		{
			sourceText(
				in: $0,
				from: storage
			)
		}.joined(separator: "\n")
		return pasteboard.setString(
			text,
			forType: type
		)
	}

	private static func isPlainText(_ type: NSPasteboard.PasteboardType) -> Bool
	{
		type == .string || type.rawValue == "NSStringPboardType"
	}

	func updateSourceAccessibilityHelp()
	{
		var sources: [String] = []
		textStorage?.enumerateAttribute(
			.conversationSourceText,
			in: NSRange(
				location: 0,
				length: textStorage?.length ?? 0
			),
			options: []
		)
		{
			value, _, _ in
			if let source = value as? String, !source.isEmpty
			{
				sources.append(source)
			}
		}
		setAccessibilityHelp(sources.isEmpty ? nil : sources.joined(separator: "\n\n"))
	}

	private func sourceText(
		in selection: NSRange,
		from storage: NSAttributedString
	) -> String
	{
		let range = NSIntersectionRange(
			selection,
			NSRange(
				location: 0,
				length: storage.length
			)
		)
		var result = ""
		let displayedText = storage.string as NSString
		storage.enumerateAttributes(
			in: range,
			options: []
		)
		{
			attributes, runRange, _ in
			guard attributes[.conversationCodeHeader] as? Bool != true
			else
			{
				return
			}
			if let source = attributes[.conversationInlineCodeSource] as? String
			{
				var sourceRange = NSRange()
				_ = storage.attribute(
					.conversationInlineCodeSource,
					at: runRange.location,
					longestEffectiveRange: &sourceRange,
					in: NSRange(
						location: 0,
						length: storage.length
					)
				)
				let original = source as NSString
				let offset = runRange.location - sourceRange.location
				if offset + runRange.length <= original.length
				{
					result += original.substring(with: NSRange(
						location: offset,
						length: runRange.length
					))
				}
			}
			else if let source = attributes[.conversationSourceText] as? String
			{
				result += source
			}
			else
			{
				let text = displayedText.substring(with: runRange)
				result += attributes[.conversationThematicBreak] as? Bool == true
					? text.replacingOccurrences(
						of: "\u{FFFC}",
						with: "---"
					) : text
			}
		}
		return result
	}
}
