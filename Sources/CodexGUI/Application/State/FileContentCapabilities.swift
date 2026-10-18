import Foundation

/// Format capabilities shared by byte loading and source/preview presentation.
/// Services still validate bytes before admitting a document.
enum FileContentCapabilities: Sendable
{
	case source
	case markdown
	case rasterImage
	case svg
	case pdf

	init(path: String)
	{
		switch URL(fileURLWithPath: path).pathExtension.lowercased()
		{
		case "md", "markdown": self = .markdown
		case "png", "jpg", "jpeg", "gif", "tif", "tiff", "bmp", "heic", "webp":
			self = .rasterImage
		case "svg": self = .svg
		case "pdf": self = .pdf
		default: self = .source
		}
	}

	var hasSource: Bool
	{
		switch self
		{
		case .source, .markdown, .svg: true
		case .rasterImage, .pdf: false
		}
	}

	var supportsSourceAndPreview: Bool
	{
		hasSource && hasRichPreview
	}

	var hasRichPreview: Bool
	{
		self != .source
	}
}
