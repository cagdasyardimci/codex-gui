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
