import Foundation

/// Splits qualified entry IDs at their first colon, retaining empty parts and the full item suffix.
struct ConversationEntryIdentity: Equatable
{
	let turnID: String
	let itemID: String

	init?(_ entryID: String)
	{
		guard let separator = entryID.firstIndex(of: ":")
		else
		{
			return nil
		}
		turnID = String(entryID[..<separator])
		itemID = String(entryID[entryID.index(after: separator)...])
	}

	/// Grouping also accepts unqualified IDs, using the entire ID as its turn identity.
	static func turnIDWithFallback(_ entryID: String) -> String
	{
		ConversationEntryIdentity(entryID)?.turnID ?? entryID
	}
}
