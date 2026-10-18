import AppKit

/// Native rich content keeps its original source available to selection copy and accessible help.
@MainActor
final class MarkdownTextView: NSTextView
{
	private var updatingFrameSize = false
	private let expandedImagePreview = ExpandedImagePreview()

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		loadWebLinkFavicons()
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	func loadWebLinkFavicons()
	{
		guard let textStorage
		else
		{
			return
		}
		WebLinkFaviconAttachment.load(
			in: textStorage,
			invalidate: self
		)
	}

	func installContent(_ content: NSAttributedString)
	{
		textStorage?.setAttributedString(content)
		updateSourceAccessibilityHelp()
		loadWebLinkFavicons()
	}

	override func viewWillMove(toWindow newWindow: NSWindow?)
	{
		if newWindow !== window
		{
			expandedImagePreview.dismiss()
		}
		super.viewWillMove(toWindow: newWindow)
	}

	func dismissExpandedImage()
	{
		expandedImagePreview.dismiss()
	}

	override func mouseDown(with event: NSEvent)
	{
		if let window, let path = imagePath(at: convert(
			event.locationInWindow,
			from: nil
		))
		{
			expandedImagePreview.present(
				path: path,
				name: LocalAttachmentURL.resolve(path)?.lastPathComponent ?? "Image",
				in: window
			)
			return
		}
		super.mouseDown(with: event)
	}

	private func imagePath(at point: NSPoint) -> String?
	{
		guard let container = textContainer, let manager = layoutManager,
				let storage = textStorage, storage.length > 0
		else
		{
			return nil
		}
		let origin = textContainerOrigin
		let location = NSPoint(
			x: point.x - origin.x,
			y: point.y - origin.y
		)
		let glyph = manager.glyphIndex(
			for: location,
			in: container
		)
		guard glyph < manager.numberOfGlyphs
		else
		{
			return nil
		}
		let frame = manager.boundingRect(
			forGlyphRange: NSRange(
				location: glyph,
				length: 1
			),
			in: container
		)
		guard frame.contains(location)
		else
		{
			return nil
		}
		let character = manager.characterIndexForGlyph(at: glyph)
		guard character < storage.length,
				let gallery = storage.attribute(
				.attachment,
				at: character,
				effectiveRange: nil
				) as? MarkdownImageGalleryAttachment
		else
		{
			return nil
		}
		return gallery.path(
			at: location,
			in: frame
		)
	}

	override func draw(_ dirtyRect: NSRect)
	{
		MarkdownTextDrawing.withAntialiasing
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
		// NSTextView scrolls its caret during frame changes. Callers preserve their
		// reading position across those changes.
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
			.markdownSourceText,
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
			guard attributes[.markdownCodeHeader] as? Bool != true
			else
			{
				return
			}
			if let source = attributes[.markdownInlineCodeSource] as? String
			{
				var sourceRange = NSRange()
				_ = storage.attribute(
					.markdownInlineCodeSource,
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
			else if let source = attributes[.markdownSourceText] as? String
			{
				result += source
			}
			else
			{
				let text = displayedText.substring(with: runRange)
				result += attributes[.markdownThematicBreak] as? Bool == true
					? text.replacingOccurrences(
						of: "\u{FFFC}",
						with: "---"
					) : text
			}
		}
		return result
	}
}
