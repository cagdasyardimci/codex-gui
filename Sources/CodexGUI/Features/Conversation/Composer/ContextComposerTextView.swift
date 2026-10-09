import AppKit
import UniformTypeIdentifiers

/// Intercepts image paste/drop while retaining ordinary text editing and file drops.
final class ContextComposerTextView: NSTextView
{
	var onImage: ((NSImage, String) -> Void)?
	var onImageSource: ((DraftImageSource, String) -> Void)?
	var acceptsImageAttachments = true
	var imagePasteboard: NSPasteboard = .general
	var placeholder = "Message Codex…"
	{
		didSet
		{
			needsDisplay = true
		}
	}

	override var string: String
	{
		didSet
		{
			needsDisplay = true
		}
	}

	override func didChangeText()
	{
		super.didChangeText()
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		super.draw(dirtyRect)
		guard string.isEmpty
		else
		{
			return
		}
		var origin = textContainerOrigin
		origin.x += textContainer?.lineFragmentPadding ?? 0
		(placeholder as NSString).draw(
			at: origin,
			withAttributes: [
				.font: font ?? NSFont.systemFont(ofSize: 15),
				.foregroundColor: NSColor.placeholderTextColor,
			]
		)
	}

	override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool
	{
		if menuItem.action == #selector(NSText.paste(_:)), canPasteImage
		{
			return true
		}
		return super.validateMenuItem(menuItem)
	}

	override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool
	{
		if item.action == #selector(NSText.paste(_:)), canPasteImage
		{
			return true
		}
		return super.validateUserInterfaceItem(item)
	}

	private var canPasteImage: Bool
	{
		guard isEditable, acceptsImageAttachments
		else
		{
			return false
		}
		if onImageSource != nil
		{
			return hasImageSource(in: imagePasteboard)
		}
		return onImage != nil && NSImage(pasteboard: imagePasteboard) != nil
	}

	override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation
	{
		if isEditable, acceptsImageAttachments, onImageSource != nil
		{
			return hasImageSource(in: sender.draggingPasteboard)
				? .copy : super.draggingEntered(sender)
		}
		if isEditable, acceptsImageAttachments, onImage != nil,
			draggedImage(from: sender.draggingPasteboard) != nil
		{
			return .copy
		}
		return super.draggingEntered(sender)
	}

	override func paste(_ sender: Any?)
	{
		if isEditable, acceptsImageAttachments, let onImageSource
		{
			let sources = pastedImageSources(from: imagePasteboard)
			if !sources.isEmpty
			{
				for source in sources
				{
					onImageSource(
						source,
						"Pasted image"
					)
				}
				return
			}
		}
		if isEditable, acceptsImageAttachments, let onImage,
			let image = NSImage(pasteboard: imagePasteboard)
		{
			onImage(
				image,
				"Pasted image"
			)
			return
		}
		super.paste(sender)
	}

	override func performDragOperation(_ sender: NSDraggingInfo) -> Bool
	{
		if isEditable, acceptsImageAttachments, let onImageSource,
			let (source, title) = draggedImageSource(from: sender.draggingPasteboard)
		{
			onImageSource(
				source,
				title
			)
			return true
		}
		if isEditable, acceptsImageAttachments, let onImage,
			let (image, title) = draggedImage(from: sender.draggingPasteboard)
		{
			onImage(
				image,
				title
			)
			return true
		}
		return super.performDragOperation(sender)
	}

	private func hasImageSource(in pasteboard: NSPasteboard) -> Bool
	{
		encodedImageType(in: pasteboard) != nil || imageFileURL(in: pasteboard) != nil
			|| pasteboard.canReadObject(
				forClasses: [NSImage.self],
				options: nil
			)
	}

	private func encodedImageType(in pasteboard: NSPasteboard) -> NSPasteboard.PasteboardType?
	{
		encodedImageType(in: pasteboard.types ?? [])
	}

	private func encodedImageType(
		in types: [NSPasteboard.PasteboardType]
	) -> NSPasteboard.PasteboardType?
	{
		if let preferred = [.png, .tiff].first(where: types.contains)
		{
			return preferred
		}
		return types.first
		{
			UTType($0.rawValue)?.conforms(to: .image) == true
		}
	}

	private func imageFileURL(in pasteboard: NSPasteboard) -> URL?
	{
		guard let url =
			(pasteboard.readObjects(
				forClasses: [NSURL.self],
				options: [.urlReadingFileURLsOnly: true]
			) as? [URL])?.first(where:
				{
					UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true
				})
		else
		{
			return nil
		}
		return url
	}

	private func pastedImageSources(from pasteboard: NSPasteboard) -> [DraftImageSource]
	{
		// Each item is one attachment; PNG/TIFF representations of it are alternatives.
		let sources = (pasteboard.pasteboardItems ?? []).compactMap
		{
			item -> DraftImageSource? in
			if let type = encodedImageType(in: item.types), let data = item.data(forType: type)
			{
				return .data(data)
			}
			if let path = item.string(forType: .fileURL), let url = URL(string: path),
				url.isFileURL,
				UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
			{
				return .file(url)
			}
			return nil
		}
		if !sources.isEmpty
		{
			return sources
		}
		// Retain AppKit conversion for clipboard formats without an encoded image source.
		return (pasteboard.readObjects(
			forClasses: [NSImage.self],
			options: nil
		) as? [NSImage])?
			.compactMap
			{
				DraftImageSource(image: $0)
			} ?? []
	}

	private func draggedImageSource(from pasteboard: NSPasteboard) -> (DraftImageSource, String)?
	{
		if let url = imageFileURL(in: pasteboard)
		{
			return (.file(url), url.lastPathComponent)
		}
		if let type = encodedImageType(in: pasteboard), let data = pasteboard.data(forType: type)
		{
			return (.data(data), "Dropped image")
		}
		guard let (image, title) = draggedImage(from: pasteboard),
				let source = DraftImageSource(image: image)
		else
		{
			return nil
		}
		return (source, title)
	}

	private func draggedImage(from pasteboard: NSPasteboard) -> (NSImage, String)?
	{
		if let url =
			(pasteboard.readObjects(
				forClasses: [NSURL.self],
				options: [
					.urlReadingFileURLsOnly: true
				]
			) as? [URL])?.first,
			let image = NSImage(contentsOf: url)
		{
			return (image, url.lastPathComponent)
		}
		if let image = NSImage(pasteboard: pasteboard)
		{
			return (image, "Dropped image")
		}
		return nil
	}
}
