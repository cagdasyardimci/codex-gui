import Foundation

enum ConversationKey: Hashable
{
	case newChat
	case thread(String)

	var threadID: String?
	{
		switch self
		{
		case .newChat: return nil
		case .thread(let id): return id
		}
	}
}
