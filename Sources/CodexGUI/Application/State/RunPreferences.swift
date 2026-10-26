import Foundation

/// Captured before submitting a turn. Changing the next-turn controls never changes a running turn.
struct RunPreferences: Codable, Equatable
{
	let approvalMode: ApprovalMode
	let fastMode: Bool
	let configurationDefaults: RunConfigurationDefaults?

	init(
		approvalMode: ApprovalMode,
		fastMode: Bool,
		configurationDefaults: RunConfigurationDefaults? = nil
	)
	{
		self.approvalMode = approvalMode
		self.configurationDefaults = configurationDefaults
		if let tier = configurationDefaults?.serviceTier
		{
			self.fastMode = tier == "priority" || tier == "fast"
		}
		else
		{
			self.fastMode = fastMode
		}
	}

	func withComposerFastMode(_ fastMode: Bool) -> RunPreferences
	{
		RunPreferences(
			approvalMode: approvalMode,
			fastMode: fastMode,
			configurationDefaults: configurationDefaults
		)
	}

	// The initial selection is explicit and conservative instead of inheriting unseen backend
	// policy.
	static let standard = RunPreferences(
		approvalMode: .askForApproval,
		fastMode: false
	)

	var approvalPolicy: TurnApprovalPolicy
	{
		configurationDefaults?.approvalPolicy
			?? (approvalMode == .fullAccess ? .never : .onRequest)
	}

	var approvalsReviewer: TurnApprovalsReviewer
	{
		configurationDefaults?.approvalPolicy == nil && approvalMode == .approveForMe
			? .autoReview : .user
	}

	var sandboxPolicy: TurnSandboxPolicy
	{
		switch configurationDefaults?.sandboxMode
		{
		case .readOnly: return .readOnly
		case .dangerFullAccess: return .dangerFullAccess
		case .workspaceWrite:
			return .configuredWorkspaceWrite(
				networkAccess: configurationDefaults?.networkAccess ?? false
			)
		case nil:
			if approvalMode == .fullAccess
			{
				return .dangerFullAccess
			}
			if let networkAccess = configurationDefaults?.networkAccess
			{
				return .configuredWorkspaceWrite(networkAccess: networkAccess)
			}
			return .workspaceWrite
		}
	}

	var serviceTierForTurn: String
	{
		configurationDefaults?.serviceTier ?? (fastMode ? "priority" : "default")
	}
}

extension WorkspaceModel
{
	var runPreferencesForSubmission: RunPreferences
	{
		preferences.runPreferences.withComposerFastMode(composerSelection.fastMode)
	}

	var serviceTierForSubmission: String?
	{
		let preferences = runPreferencesForSubmission
		return preferences.configurationDefaults?.serviceTier
			?? (preferences.fastMode ? FastModeAvailability.serviceTier(in: self) : "default")
	}
}
