import Foundation

enum ComposerContextError: LocalizedError
{
	case missingFile(String)
	case missingImage(String)
	case invalidPath(String)

	var errorDescription: String?
	{
		switch self
		{
		case .missingFile(let path): "Referenced file is unavailable: \(path)"
		case .missingImage(let path): "Attached image is unavailable: \(path)"
		case .invalidPath(let path): "Reference is outside this project: \(path)"
		}
	}
}
