import Foundation

/// Captured before submitting a turn. Changing the next-turn controls never changes a running turn.
struct RunPreferences: Codable, Equatable
{
	let approvalMode: ApprovalMode
	let fastMode: Bool
	let composerServiceTier: String?
	let configurationDefaults: RunConfigurationDefaults?

	init(
		approvalMode: ApprovalMode,
		fastMode: Bool,
		configurationDefaults: RunConfigurationDefaults? = nil,
		composerServiceTier: String? = nil
	)
	{
		self.approvalMode = approvalMode
		self.configurationDefaults = configurationDefaults
		self.composerServiceTier = composerServiceTier
		if let tier = composerServiceTier ?? configurationDefaults?.serviceTier
		{
			self.fastMode = tier == "priority" || tier == "fast"
		}
		else
		{
			self.fastMode = fastMode
		}
	}

	func withComposerSpeed(
		fastMode: Bool,
		serviceTier: String?
	) -> RunPreferences
	{
		RunPreferences(
			approvalMode: approvalMode,
			fastMode: fastMode,
			configurationDefaults: configurationDefaults,
			composerServiceTier: serviceTier
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
		composerServiceTier ?? configurationDefaults?
			.serviceTier ?? (fastMode ? "priority" : "default")
	}
}

extension WorkspaceModel
{
	var runPreferencesForSubmission: RunPreferences
	{
		let selection = composerSelection
		let tier = composerServiceTierForSubmission
		return preferences.runPreferences.withComposerSpeed(
			fastMode: selection.fastMode,
			serviceTier: tier == preferences.runPreferences.configurationDefaults?
				.serviceTier ? nil : tier
		)
	}

	var serviceTierForSubmission: String?
	{
		composerServiceTierForSubmission
			?? (composerSelection.fastMode ? FastModeAvailability.serviceTier(in: self) : "default")
	}

	private var composerServiceTierForSubmission: String?
	{
		guard let tier = composerSelection.serviceTier
		else
		{
			return nil
		}
		return FastModeAvailability.resolvedTier(
			tier,
			in: self
		)
	}
}
