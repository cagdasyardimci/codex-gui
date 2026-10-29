import Foundation

struct QueuedComposerMessage: Codable, Equatable, Identifiable
{
	let id: UUID
	let text: String
	let context: [ComposerContextItem]
	let modelID: String?
	let effort: String?
	let preferences: RunPreferences
	let skills: [SkillReference]
	let collaborationMode: CollaborationMode?
	let serviceTier: String?
	var serverID: String? = nil
	enum SteeringPhase: String, Codable
	{
		case deleting, ready, sending
	}
	var steeringInputJSON: Data? = nil
	var steeringPhase: SteeringPhase? = nil
	var enqueueUncertain: Bool? = nil
	func editing(
		text: String,
		context: [ComposerContextItem]? = nil
	) -> QueuedComposerMessage
	{
		QueuedComposerMessage(
			id: id,
			text: text,
			context: context ?? self.context,
			modelID: modelID,
			effort: effort,
			preferences: preferences,
			skills: skills,
			collaborationMode: collaborationMode,
			serviceTier: serviceTier,
			serverID: serverID,
			steeringPhase: steeringPhase,
			enqueueUncertain: enqueueUncertain
		)
	}

}
