import Foundation

extension WorkspaceStoreInputs
{
	func readAloud(
		entryID: String,
		text: String
	)
	{
		guard let threadID = store.model.conversations.selectedConversation.threadID
		else
		{
			return
		}
		store.dispatch(.readAloud(.requested(ReadAloudRequest(
			context: store.operationContext(threadID: threadID),
			entryID: entryID,
			text: text
		))))
	}

	func stopReadAloud()
	{
		store.dispatch(.readAloud(.stopRequested))
	}
}
