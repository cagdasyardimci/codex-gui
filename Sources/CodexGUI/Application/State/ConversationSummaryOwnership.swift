import Foundation

/// Filesystem validation is performed before proposing the metadata read.
struct ConversationSummaryOwnership: Equatable
{
	let summaryCWD: String
	let canonicalCheckoutPath: String
}
