import Foundation

struct ComposerSubmission
{
	let context: OperationContext
	let conversation: ConversationKey
	let draft: ComposerDraft
	let inputs: [TurnInput]
	let skills: [SkillReference]
	let modelID: String?
	let effort: String?
	let preferences: RunPreferences
	let retainedContextRequestID: UUID
	var projectContextRevision: Int? = nil
	var collaborationMode: CollaborationMode? = nil
	var serviceTier: String? = nil
}
