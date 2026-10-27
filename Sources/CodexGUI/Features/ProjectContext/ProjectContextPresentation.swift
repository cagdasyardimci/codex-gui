import Foundation

struct ProjectContextPresentation: Equatable
{
	let context: ProjectContext
	let models: [ModelOption]
	let skills: [ProjectSkillSelection]
	let ownerIdentity: String?
	let draftOwnerIdentity: String?

	init(
		context: ProjectContext,
		models: [ModelOption],
		skills: [ProjectSkillSelection],
		ownerIdentity: String?,
		draftOwnerIdentity: String?
	)
	{
		self.context = context
		self.models = models
		self.skills = skills
		self.ownerIdentity = ownerIdentity
		self.draftOwnerIdentity = draftOwnerIdentity
	}

	init(
		_ snapshot: ConversationSnapshot,
		ownerIdentity: String? = nil
	)
	{
		context = snapshot.projectContext
		models = snapshot.models
		skills = snapshot.skillCatalog?.skills.filter(\.enabled).map
		{
			ProjectSkillSelection(
				name: $0.name,
				description: $0.description,
				path: $0.path
			)
		} ?? []
		let owner = FeaturePresentationOwner(
			snapshot,
			storeIdentity: ownerIdentity
		)
		self.ownerIdentity = owner.projectIdentity
		draftOwnerIdentity = owner.draftIdentity(lifetime: snapshot.composerDraftLifetime)
	}
}
