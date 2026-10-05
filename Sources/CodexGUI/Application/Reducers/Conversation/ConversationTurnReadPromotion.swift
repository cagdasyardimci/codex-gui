import Foundation

/// A preview producer may acquire one foreground or neighborhood consumer.
struct ConversationTurnReadPromotion: Equatable
{
	let producer: ConversationTurnReadOperation
	let consumer: ConversationTurnReadOperation
}
