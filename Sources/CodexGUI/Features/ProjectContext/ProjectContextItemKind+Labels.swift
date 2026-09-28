import Foundation

extension ProjectContextItemKind
{
	var displayTitle: String
	{
		switch self
		{
		case .specification: "Specification"
		case .referenceFile: "Reference File"
		case .note: "Note"
		case .decision: "Decision"
		}
	}
}
