import Foundation

extension ConversationBookmarkKind
{
	var displayTitle: String
	{
		switch self
		{
		case .userRequest: "Request"
		case .answer: "Answer"
		case .decision: "Decision"
		case .changedFile: "Changed File"
		case .failure: "Failure"
		}
	}
}
