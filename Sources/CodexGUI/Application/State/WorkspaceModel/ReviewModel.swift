import Foundation

struct ConversationReviewModel
{
	var turns: [ReviewTurn] = []
	var parsedChanges: [String: ReviewParsedChanges] = [:]
	var selectedTurnID: String?
	var sourceRevision = -1
	var markerRevision = 0
	var loadedMarkerSnapshot: [ReviewMarkerIdentity]?
	var markerFingerprints: [ReviewReference: String] = [:]
	var pendingMarkerLoad: ReviewMarkerReadOperation?
	var pendingMarkerWrites: [ReviewReference: ReviewMarkerWriteOperation] = [:]
	var error: String?
}

struct ReviewModel
{
	var conversations: [ConversationKey: ConversationReviewModel] = [:]
	var observationContext: OperationContext?
}
