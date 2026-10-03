import Foundation

enum ComposerContextKind: String, Codable
{
	case fileReference
	case textExcerpt
	case image

	var title: String
	{
		switch self
		{
		case .fileReference: "File reference"
		case .textExcerpt: "Code excerpt"
		case .image: "Image"
		}
	}
}
