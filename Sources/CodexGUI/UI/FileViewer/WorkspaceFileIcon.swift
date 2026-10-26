import AppKit

/// File artwork shared by workspace browsing and repository comparisons.
@MainActor
enum WorkspaceFileIcon
{
	static func image(
		relativePath: String,
		isDirectory: Bool = false,
		isSymbolicLink: Bool = false,
		size: CGFloat = 16
	) -> NSImage
	{
		let type = WorkspaceFileTypePresentation(
			relativePath: relativePath,
			isDirectory: isDirectory,
			isSymbolicLink: isSymbolicLink
		)
		return image(
			for: type,
			relativePath: relativePath,
			size: size
		)
	}

	static func image(
		for type: WorkspaceFileTypePresentation,
		relativePath: String? = nil,
		size: CGFloat = 16
	) -> NSImage
	{
		guard let asset = asset(
			for: type,
			relativePath: relativePath
		)
		else
		{
			return swiftImage(
				size: size,
				accessibilityDescription: type.description
			)
		}
		return DesktopIcons.image(
			asset,
			size: size,
			accessibilityDescription: type.description
		)
	}

	/// Metadata takes precedence over the extension for links, folders and Swift source.
	static func asset(
		for type: WorkspaceFileTypePresentation,
		relativePath: String? = nil
	) -> DesktopIcon?
	{
		switch type.symbol
		{
		case "link": return .link
		case "folder": return .folder
		case "swift": return nil
		default: break
		}

		if let relativePath
		{
			switch URL(fileURLWithPath: relativePath).pathExtension.lowercased()
			{
			case "png", "jpg", "jpeg", "gif", "heic", "webp", "svg", "tiff", "bmp":
				return .fileImage
			case "pdf", "doc", "docx", "rtf", "md", "markdown", "txt":
				return .fileDocument
			case "json", "yaml", "yml", "toml", "js", "ts", "tsx", "jsx", "py", "html", "css":
				return .fileCode
			case "xls", "xlsx", "csv", "tsv": return .fileSpreadsheet
			case "ppt", "pptx", "key": return .filePresentation
			case "mp3", "wav", "m4a", "aac", "flac": return .fileAudio
			case "mp4", "mov", "webm", "mkv": return .fileVideo
			case "zip", "gz", "tar", "7z": return .fileZip
			default: break
			}
		}

		switch type.symbol
		{
		case "doc.text": return .fileDocument
		case "curlybraces": return .fileCode
		default: return .fileBlank
		}
	}

	/// Document search artwork shared by the Files and Changes toolbars.
	static func searchImage(
		size: CGFloat = 16,
		accessibilityDescription: String? = nil
	) -> NSImage
	{
		let image = NSImage(
			size: NSSize(
				width: size,
				height: size
			),
			flipped: true
		)
		{
			bounds in
			NSGraphicsContext.saveGraphicsState()
			defer
			{
				NSGraphicsContext.restoreGraphicsState()
			}
			let transform = AffineTransform(scale: bounds.width / 24)
			(transform as NSAffineTransform).concat()
			NSColor.black.setStroke()
			let page = NSBezierPath()
			page.move(to: NSPoint(
				x: 10,
				y: 21
			))
			page.line(to: NSPoint(
				x: 5,
				y: 21
			))
			page.curve(
				to: NSPoint(
					x: 3,
					y: 19
				),
				controlPoint1: NSPoint(
					x: 3.5,
					y: 21
				),
				controlPoint2: NSPoint(
					x: 3,
					y: 20.5
				)
			)
			page.line(to: NSPoint(
				x: 3,
				y: 5
			))
			page.curve(
				to: NSPoint(
					x: 5,
					y: 3
				),
				controlPoint1: NSPoint(
					x: 3,
					y: 3.5
				),
				controlPoint2: NSPoint(
					x: 3.5,
					y: 3
				)
			)
			page.line(to: NSPoint(
				x: 14,
				y: 3
			))
			page.line(to: NSPoint(
				x: 19,
				y: 8
			))
			page.line(to: NSPoint(
				x: 19,
				y: 10
			))
			page.move(to: NSPoint(
				x: 13,
				y: 3
			))
			page.line(to: NSPoint(
				x: 13,
				y: 8
			))
			page.line(to: NSPoint(
				x: 19,
				y: 8
			))
			page.move(to: NSPoint(
				x: 18,
				y: 19
			))
			page.line(to: NSPoint(
				x: 21,
				y: 22
			))
			let lens = NSBezierPath(ovalIn: NSRect(
				x: 12,
				y: 13,
				width: 7,
				height: 7
			))
			for path in [page, lens]
			{
				path.lineWidth = 1.8
				path.lineCapStyle = .round
				path.lineJoinStyle = .round
				path.stroke()
			}
			return true
		}
		image.isTemplate = true
		image.accessibilityDescription = accessibilityDescription
		return image
	}

	static func swiftImage(
		size: CGFloat = 16,
		accessibilityDescription: String? = nil
	) -> NSImage
	{
		// The package has no Swift mark; Apple's native vector symbol supplies its shape.
		let source = NSImage(
			systemSymbolName: "swift",
			accessibilityDescription: accessibilityDescription
		)!
		let image = NSImage(
			size: NSSize(
				width: size,
				height: size
			),
			flipped: false
		)
		{
			bounds in
			source.draw(in: bounds)
			NSColor(
				calibratedRed: 1,
				green: 0.58,
				blue: 0.26,
				alpha: 1
			).setFill()
			bounds.fill(using: .sourceIn)
			return true
		}
		image.isTemplate = false
		image.accessibilityDescription = accessibilityDescription
		return image
	}
}
