import Foundation

struct ConversationPresentation: Equatable
{
	struct Transcript: Equatable
	{
		let owner: FeaturePresentationOwner
		let entries: [ConversationEntry]
		var turnTimings: [ConversationTurnTiming] = []
		var activeThreadID: String? = nil
		var activeTurnID: String? = nil
		let canLoadEarlierTurns: Bool
		var selectedThreadID: String?
		{
			owner.selectedThreadID
		}
	}

	struct Navigation: Equatable
	{
		var turnReferences: [ConversationTurnReference] = []
		var turnPreviews: [ConversationTurnPreview] = []
		var turnPreviewErrors: [String: String] = [:]
		var canLoadEarlierTurnReferences = false
		let owner: FeaturePresentationOwner
		let bookmarks: [ConversationBookmark]
		let navigationTargets: [ConversationJumpTarget]
	}

	struct Status: Equatable
	{
		let owner: FeaturePresentationOwner
		let executionState: ExecutionState
		let isLocked: Bool
		let statusMessage: String?
		let activeThreadID: String?
		let activeExecutionState: ExecutionState?
		let activePlan: TurnPlanUpdate?
		let activeActivity: String?
		let jumpError: String?
		let jumpLoading: Bool
		var selectedThreadID: String?
		{
			owner.selectedThreadID
		}
	}

	struct RequestContext: Equatable
	{
		let owner: FeaturePresentationOwner
		let includedItemCount: Int
		let selectedSkill: ProjectSkillSelection?
		let selectedSkillTitle: String?
		let skillAvailable: Bool
		let includedContextText: String
		let draftContextSummary: String

		init(
			_ snapshot: ConversationSnapshot,
			owner: FeaturePresentationOwner
		)
		{
			self.owner = owner
			includedItemCount = snapshot.projectContext.items.filter(\.isIncluded).count
			selectedSkill = snapshot.projectContext.selectedSkill
			selectedSkillTitle = selectedSkill.map
			{
				selected in
				let matching = snapshot.skillCatalog?.skills
					.filter
					{
						$0.name == selected.name
					} ?? []
				let skill = matching.first
				{
					$0.path == selected.path
				}
				?? (matching.count == 1 ? matching[0] : nil)
				return skill?.displayName ?? selected.name
			}
			skillAvailable = selectedSkill.map
			{
				selected in
				let matchingSkills = snapshot.skillCatalog?.skills.filter
				{
					$0.enabled && $0.name == selected.name
				} ?? []
				return matchingSkills.contains
				{
					$0.path == selected.path
				} || matchingSkills.count == 1
			} ?? false
			includedContextText = snapshot.projectContext.includedContextText
			draftContextSummary = snapshot.draftContext.map
			{
				"\($0.kind.title): \($0.detail)"
			}
			.joined(separator: "\n")
		}
	}

	struct Preferences: Equatable
	{
		let owner: FeaturePresentationOwner
		let models: [ModelOption]
		let selectedModelID: String?
		let selectedEffort: String?
		let fastMode: Bool
		let approvalMode: ApprovalMode
		var configurationDefaults: RunConfigurationDefaults? = nil
		let preferenceWarning: String?
	}

	struct Composer: Equatable
	{
		let owner: FeaturePresentationOwner
		let draftLifetime: Int
		let draft: String
		let draftContext: [ComposerContextItem]
		let reusableReferences: [ComposerContextItem]
		let canSend: Bool
		let isLocked: Bool
		let isRetryingLockedChat: Bool
		let canForkLockedChat: Bool
		let canSteer: Bool
		let planMode: Bool
		let planModeStatus: String?
		var availableSkills: [AvailableSkill] = []
		let slashCommandUnavailableReasons: [SlashCommandID: String]
		let threadTokenUsage: ThreadTokenUsage?
		let activeThreadID: String?
		let activeTurnID: String?
		let activeExecutionState: ExecutionState?
		let turnChangeRequest: GitComparisonRequest?
		var projectPath: String?
		{
			owner.projectPath
		}
		var selectedThreadID: String?
		{
			owner.selectedThreadID
		}
	}

	/// Cards retain local answers while their complete captured callback payload is unchanged.
	struct Interactions: Equatable
	{
		private struct Question: Equatable
		{
			struct Option: Equatable
			{
				let label: String
				let description: String
			}
			let id: String
			let header: String
			let question: String
			let options: [Option]
			let allowsOther: Bool
			let isSecret: Bool
		}
		private struct Key: Equatable
		{
			let id: String
			let threadID: String
			let turnID: String
			let itemID: String
			let approvalID: String?
			let kind: String
			let reason: String?
			let command: String?
			let cwd: String?
			let grantRoot: String?
			let networkHost: String?
			let networkProtocol: String?
			let questions: [Question]
			let requestedPermissions: NSDictionary?
			let additionalPermissions: NSDictionary?
			let decisions: [ApprovalDecision]?
		}
		let owner: FeaturePresentationOwner
		let values: [PendingInteraction]
		private var keys: [Key]
		{
			values.map
			{
				value in
				Key(
					id: value.id,
					threadID: value.threadId,
					turnID: value.turnId,
					itemID: value.itemId,
					approvalID: value.approvalId,
					kind: String(reflecting: value.kind),
					reason: value.reason,
					command: value.command,
					cwd: value.cwd,
					grantRoot: value.grantRoot,
					networkHost: value.networkHost,
					networkProtocol: value.networkProtocol,
					questions: value.questions.map
					{
						Question(
							id: $0.id,
							header: $0.header,
							question: $0.question,
							options: $0.options.map
							{
								Question.Option(
									label: $0.label,
									description: $0.description
								)
							},
							allowsOther: $0.allowsOther,
							isSecret: $0.isSecret
						)
					},
					requestedPermissions: value.requestedPermissions.map(NSDictionary.init),
					additionalPermissions: value.additionalPermissions.map(NSDictionary.init),
					decisions: value.availableDecisions
				)
			}
		}
		static func == (lhs: Self, rhs: Self) -> Bool
		{
			lhs.owner == rhs.owner && lhs.keys == rhs.keys
		}
	}

	let transcript: Transcript
	let navigation: Navigation
	let status: Status
	let requestContext: RequestContext
	let preferences: Preferences
	let composer: Composer
	let interactions: Interactions
	var owner: FeaturePresentationOwner
	{
		transcript.owner
	}

	init(
		_ snapshot: ConversationSnapshot,
		ownerIdentity: String? = nil
	)
	{
		let owner = FeaturePresentationOwner(
			snapshot,
			storeIdentity: ownerIdentity
		)
		transcript = Transcript(
			owner: owner,
			entries: snapshot.entries,
			turnTimings: snapshot.turnTimings,
			activeThreadID: snapshot.activeThreadID,
			activeTurnID: snapshot.activeTurnID,
			canLoadEarlierTurns: snapshot.canLoadEarlierTurns
		)
		navigation = Navigation(
			turnReferences: snapshot.turnReferences,
			turnPreviews: snapshot.turnPreviews,
			turnPreviewErrors: snapshot.turnPreviewErrors,
			canLoadEarlierTurnReferences: snapshot.canLoadEarlierTurnReferences,
			owner: owner,
			bookmarks: snapshot.projectContext.bookmarks,
			navigationTargets: snapshot.navigationTargets.filter
			{
				$0.threadID == snapshot.selectedThreadID
			}
		)
		let isViewingActiveThread =
			snapshot.activeThreadID != nil && snapshot.activeThreadID == snapshot.selectedThreadID
		status = Status(
			owner: owner,
			executionState: snapshot.executionState,
			isLocked: snapshot.chatLocked,
			statusMessage: snapshot.statusMessage,
			activeThreadID: snapshot.activeThreadID,
			activeExecutionState: snapshot.activeExecutionState,
			activePlan: isViewingActiveThread ? snapshot.activePlan : nil,
			activeActivity: isViewingActiveThread ? snapshot.activeActivity : nil,
			jumpError: snapshot.jumpError,
			jumpLoading: snapshot.jumpLoading
		)
		requestContext = RequestContext(
			snapshot,
			owner: owner
		)
		preferences = Preferences(
			owner: owner,
			models: snapshot.models,
			selectedModelID: snapshot.selectedModelID,
			selectedEffort: snapshot.selectedEffort,
			fastMode: snapshot.fastMode,
			approvalMode: snapshot.approvalMode,
			configurationDefaults: snapshot.configurationDefaults,
			preferenceWarning: snapshot.preferenceWarning
		)
		composer = Composer(
			owner: owner,
			draftLifetime: snapshot.composerDraftLifetime,
			draft: snapshot.draft,
			draftContext: snapshot.draftContext,
			reusableReferences: snapshot.reusableReferences,
			canSend: snapshot.canSend,
			isLocked: snapshot.chatLocked,
			isRetryingLockedChat: snapshot.chatLockRetrying,
			canForkLockedChat: snapshot.slashCommandUnavailableReasons[.fork] == nil,
			canSteer: snapshot.canSteer,
			planMode: snapshot.planMode,
			planModeStatus: snapshot.planModeStatus,
			availableSkills: snapshot.skillCatalog?.skills.filter(\.enabled) ?? [],
			slashCommandUnavailableReasons: snapshot.slashCommandUnavailableReasons,
			threadTokenUsage: snapshot.threadTokenUsage,
			activeThreadID: snapshot.activeThreadID,
			activeTurnID: snapshot.activeTurnID,
			activeExecutionState: snapshot.activeExecutionState,
			turnChangeRequest: snapshot.runningGitReviewRequest(owner: owner)
		)
		interactions = Interactions(
			owner: owner,
			values: snapshot.pendingInteractions
		)
	}
}
