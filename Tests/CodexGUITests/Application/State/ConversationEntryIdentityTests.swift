import Testing

@testable import CodexGUI

@Suite
struct ConversationEntryIdentityTests
{
	@Test(arguments: [
		("turn:item", "turn", "item"),
		("turn:item:part", "turn", "item:part"),
		(":item", "", "item"),
		("turn:", "turn", ""),
		(":", "", ""),
	])
	func qualifiedIdentityPreservesFullSuffixAndEmptyComponents(
		entryID: String,
		turnID: String,
		itemID: String
	) throws
	{
		let identity = try #require(ConversationEntryIdentity(entryID))
		#expect(identity.turnID == turnID)
		#expect(identity.itemID == itemID)
		#expect(ConversationEntryIdentity.turnIDWithFallback(entryID) == turnID)
	}

	@Test(arguments: ["unqualified", ""])
	func unqualifiedIdentityIsRejectedButGroupingRetainsTheEntireID(_ entryID: String)
	{
		#expect(ConversationEntryIdentity(entryID) == nil)
		#expect(ConversationEntryIdentity.turnIDWithFallback(entryID) == entryID)
	}
}
