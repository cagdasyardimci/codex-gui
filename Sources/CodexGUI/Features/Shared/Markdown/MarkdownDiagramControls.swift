import AppKit
import UniformTypeIdentifiers

/// Actions retain the displayed occurrence, so a later document cannot redirect an open menu.
@MainActor
final class MarkdownDiagramControls: NSView
{
	let attachment: MarkdownRichAttachment
	let optionsButton: NSButton = MarkdownDiagramButton()
	let expandButton: NSButton = MarkdownDiagramButton()
	var onExpand: ((NSImage) -> Void)?

	init(attachment: MarkdownRichAttachment)
	{
		self.attachment = attachment
		super.init(frame: .zero)
		for (button, symbol, label, action) in [
			(optionsButton, "ellipsis", "Diagram options", #selector(showOptions(_:))),
			(
				expandButton,
				"arrow.up.left.and.arrow.down.right",
				"Expand diagram",
				#selector(expand(_:))
			)
		]
		{
			button.image = NSImage(
				systemSymbolName: symbol,
				accessibilityDescription: label
			)
			button.imagePosition = .imageOnly
			button.isBordered = false
			button.bezelStyle = .circular
			button.toolTip = label
			button.setAccessibilityLabel(label)
			button.target = self
			button.action = action
			addSubview(button)
		}
	}

	required init?(coder: NSCoder)
	{
		return nil
	}

	override func layout()
	{
		super.layout()
		let width = max(
			0,
			min(
				32,
				(bounds.width - 4) / 2
			)
		)
		optionsButton.frame = NSRect(
			x: 0,
			y: 0,
			width: width,
			height: 32
		)
		expandButton.frame = NSRect(
			x: width + 4,
			y: 0,
			width: width,
			height: 32
		)
	}

	override func hitTest(_ point: NSPoint) -> NSView?
	{
		alphaValue == 0 ? nil : super.hitTest(point)
	}

	func setHovered(_ hovered: Bool)
	{
		let focused = window?.firstResponder as? NSView
		let hasFocus = focused.map
		{
			$0 === self || $0.isDescendant(of: self)
		} ?? false
		alphaValue = hovered || hasFocus ? 1 : 0
	}

	func makeMenu() -> NSMenu
	{
		let menu = NSMenu()
		for (title, symbol, action) in [
			("Copy as code", "chevron.left.forwardslash.chevron.right", #selector(copyCode(_:))),
			("Download image", "arrow.down.to.line", #selector(download(_:)))
		]
		{
			let item = NSMenuItem(
				title: title,
				action: action,
				keyEquivalent: ""
			)
			item.image = NSImage(
				systemSymbolName: symbol,
				accessibilityDescription: nil
			)
			item.target = self
			menu.addItem(item)
		}
		return menu
	}

	@objc private func showOptions(_ sender: NSButton)
	{
		makeMenu().popUp(
			positioning: nil,
			at: NSPoint(
				x: 0,
				y: bounds.maxY
			),
			in: self
		)
	}

	@objc private func copyCode(_ sender: Any?)
	{
		copyCode(to: .general)
	}

	func copyCode(to pasteboard: NSPasteboard)
	{
		pasteboard.clearContents()
		pasteboard.setString(
			attachment.source,
			forType: .string
		)
	}

	@objc private func download(_ sender: Any?)
	{
		guard let image = attachment.diagramImage(for: effectiveAppearance),
				let window
		else
		{
			return
		}
		MarkdownDiagramExport.save(
			image,
			in: window
		)
	}

	@objc private func expand(_ sender: Any?)
	{
		guard let image = attachment.diagramImage(for: effectiveAppearance)
		else
		{
			return
		}
		onExpand?(image)
	}
}

/// Reveal hover actions when reached through keyboard focus as well.
@MainActor
private final class MarkdownDiagramButton: NSButton
{
	override func becomeFirstResponder() -> Bool
	{
		let accepted = super.becomeFirstResponder()
		if accepted
		{
			superview?.alphaValue = 1
		}
		return accepted
	}
}

@MainActor
enum MarkdownDiagramExport
{
	static func pngData(_ image: NSImage) -> Data?
	{
		var rect = NSRect(
			origin: .zero,
			size: image.size
		)
		guard let cgImage = image.cgImage(
			forProposedRect: &rect,
			context: nil,
			hints: nil
		)
		else
		{
			return nil
		}
		return NSBitmapImageRep(cgImage: cgImage).representation(
			using: .png,
			properties: [:]
		)
	}

	struct File
	{
		let data: Data
		let contentType: UTType
		let name: String
	}

	static func file(_ image: NSImage) -> File?
	{
		if let vector = image as? MarkdownSVGImage, !vector.svgData.isEmpty
		{
			return File(
				data: vector.svgData,
				contentType: .svg,
				name: "diagram.svg"
			)
		}
		guard let data = pngData(image)
		else
		{
			return nil
		}
		return File(
			data: data,
			contentType: .png,
			name: "diagram.png"
		)
	}

	static func save(
		_ image: NSImage,
		in window: NSWindow
	)
	{
		guard let file = file(image)
		else
		{
			return
		}
		let panel = NSSavePanel()
		panel.allowedContentTypes = [file.contentType]
		panel.nameFieldStringValue = file.name
		panel.beginSheetModal(for: window)
		{
			response in
			guard response == .OK, let url = panel.url
			else
			{
				return
			}
			do
			{
				try file.data.write(
					to: url,
					options: .atomic
				)
			}
			catch
			{
				NSAlert(error: error).beginSheetModal(for: window)
			}
		}
	}
}
