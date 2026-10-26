import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct ConfigurationDefaultsTests
{
	@Test func confirmedSettingsRemainIndependentAndComposerOverridesAreExplicit() throws
	{
		var model = fixture()
		let context = context(model)
		let update = try #require(RunConfigurationDefaultsUpdate(
			effectiveConfig: [
				"approval_policy": "never",
				"sandbox_mode": "read-only",
				"sandbox_workspace_write": ["network_access": true],
				"service_tier": "flex",
			],
			editedKeys: ["sandbox_mode", "service_tier"]
		))
		let reduction = PreferenceReducer.reduce(
			&model,
			.preferences(.configurationDefaultsApplied(
				context,
				update
			))
		)
		let captured = model.runPreferencesForSubmission
		#expect(captured.approvalPolicy == .never)
		#expect(captured.sandboxPolicy.protocolValue["type"] as? String == "readOnly")
		#expect(model.serviceTierForSubmission == "flex")
		#expect(!captured.fastMode)
		#expect(reduction.effects.count == 1)
		#expect(reduction.effects.contains
		{
			if case .persistPreference(let write) = $0,
				case .run(let value) = write.value
			{
				return write.context == context && value == captured
			}
			return false
		})
		#expect(WorkspaceSelectors(
			model: model,
			now: Date()
		).runPreferences == captured)

		_ = PreferenceReducer.reduce(
			&model,
			.preferences(.approvalModeSelected(
				context,
				.askForApproval
			))
		)
		#expect(model.runPreferencesForSubmission.approvalPolicy == .onRequest)
		#expect(model.runPreferencesForSubmission.sandboxPolicy.protocolValue["type"] as? String
			== "workspaceWrite")
		#expect(model.runPreferencesForSubmission.sandboxPolicy.protocolValue["networkAccess"]
			as? Bool == false)
		#expect(model.serviceTierForSubmission == "flex")
		#expect(captured.approvalPolicy == .never)
		#expect(captured.serviceTierForTurn == "flex")

		_ = PreferenceReducer.reduce(
			&model,
			.preferences(.fastModeSelected(
				context,
				false
			))
		)
		#expect(model.preferences.runPreferences.configurationDefaults == nil)
		#expect(model.serviceTierForSubmission == "default")
	}

	@Test func speedSaveDoesNotImportUnrelatedPermissionsAndForeignSaveIsRejected() throws
	{
		var model = fixture()
		let update = try #require(RunConfigurationDefaultsUpdate(
			effectiveConfig: [
				"approval_policy": "never",
				"sandbox_mode": "danger-full-access",
				"service_tier": "priority",
			],
			editedKeys: ["service_tier"]
		))
		let original = model.preferences.runPreferences
		var stale = context(model)
		stale = OperationContext(
			workspace: stale.workspace,
			generation: stale.generation + 1,
			requestID: stale.requestID
		)
		let rejected = PreferenceReducer.reduce(
			&model,
			.preferences(.configurationDefaultsApplied(
				stale,
				update
			))
		)
		#expect(rejected.effects.isEmpty)
		#expect(model.preferences.runPreferences == original)
		_ = PreferenceReducer.reduce(
			&model,
			.preferences(.configurationDefaultsApplied(
				context(model),
				update
			))
		)
		#expect(model.runPreferencesForSubmission.approvalPolicy == .onRequest)
		#expect(model.runPreferencesForSubmission.sandboxPolicy.protocolValue["type"] as? String
			== "workspaceWrite")
		#expect(model.runPreferencesForSubmission.fastMode)
		#expect(model.serviceTierForSubmission == "priority")
		#expect(RunConfigurationDefaultsUpdate(
			effectiveConfig: [:],
			editedKeys: ["web_search"]
		)
			== nil)
	}

	@Test func workspaceNetworkPolicyPersistsAndLegacyPreferencesStillDecode() throws
	{
		var model = fixture()
		let update = try #require(RunConfigurationDefaultsUpdate(
			effectiveConfig: [
				"approval_policy": "on-request",
				"sandbox_mode": "workspace-write",
				"sandbox_workspace_write": ["network_access": true],
			],
			editedKeys: ["sandbox_workspace_write.network_access"]
		))
		_ = PreferenceReducer.reduce(
			&model,
			.preferences(.configurationDefaultsApplied(
				context(model),
				update
			))
		)
		let preferences = model.runPreferencesForSubmission
		#expect(preferences.sandboxPolicy.protocolValue["networkAccess"] as? Bool == true)
		let encoded = try JSONEncoder().encode(preferences)
		let restored = try JSONDecoder().decode(
			RunPreferences.self,
			from: encoded
		)
		#expect(restored == preferences)
		let legacy = Data(#"{"approvalMode":"fullAccess","fastMode":false}"#.utf8)
		let decoded = try JSONDecoder().decode(
			RunPreferences.self,
			from: legacy
		)
		#expect(decoded.configurationDefaults == nil)
		#expect(decoded.approvalPolicy == .never)
		#expect(decoded.sandboxPolicy.protocolValue["type"] as? String == "dangerFullAccess")
	}

	@Test func unsupportedPermissionMemberRejectsWholeGroupWhileTierRemainsIndependent() throws
	{
		let configurations: [[String: Any]] = [
			["approval_policy": ["reject": ["sandbox_approval": true]],
				"sandbox_mode": "workspace-write"],
			["approval_policy": "future-policy", "sandbox_mode": "read-only"],
			["approval_policy": "never", "sandbox_mode": "future-sandbox"],
			["approval_policy": "never",
				"sandbox_mode": "workspace-write",
				"sandbox_workspace_write": ["network_access": "enabled"]],
		]
		for var configuration in configurations
		{
			configuration["service_tier"] = "flex"
			if configuration["sandbox_workspace_write"] == nil
			{
				configuration["sandbox_workspace_write"] = ["network_access": true]
			}
			#expect(RunConfigurationDefaultsUpdate(
				effectiveConfig: configuration,
				editedKeys: ["sandbox_mode"]
			) == nil)
			let tierOnly = try #require(RunConfigurationDefaultsUpdate(
				effectiveConfig: configuration,
				editedKeys: ["sandbox_mode", "service_tier"]
			))
			#expect(tierOnly.keys == [.serviceTier])
			#expect(!tierOnly.values.hasPermissionOverrides)
			var existing = RunConfigurationDefaults(
				approvalPolicy: .onRequest,
				sandboxMode: .readOnly,
				networkAccess: false,
				serviceTier: "default"
			)
			existing.apply(tierOnly)
			#expect(existing.approvalPolicy == .onRequest)
			#expect(existing.sandboxMode == .readOnly)
			#expect(existing.networkAccess == false)
			#expect(existing.serviceTier == "flex")
		}
	}

	@Test func clearingConfirmedOverridesPreservesUneditedTierThenReturnsToComposerPresets() throws
	{
		var model = fixture()
		model.preferences.runPreferences = RunPreferences(
			approvalMode: .askForApproval,
			fastMode: false,
			configurationDefaults: RunConfigurationDefaults(
				approvalPolicy: .never,
				sandboxMode: .readOnly,
				networkAccess: true,
				serviceTier: "flex"
			)
		)
		let clearedPermissions = try #require(RunConfigurationDefaultsUpdate(
			effectiveConfig: [:],
			editedKeys: ["sandbox_mode"]
		))
		#expect(clearedPermissions.keys == [.approvalPolicy, .sandboxMode, .networkAccess])
		_ = PreferenceReducer.reduce(
			&model,
			.preferences(.configurationDefaultsApplied(
				context(model),
				clearedPermissions
			))
		)
		#expect(model.preferences.runPreferences.configurationDefaults
			== RunConfigurationDefaults(serviceTier: "flex"))
		#expect(model.runPreferencesForSubmission.approvalPolicy == .onRequest)
		#expect(model.runPreferencesForSubmission.sandboxPolicy.protocolValue["type"] as? String
			== "workspaceWrite")
		#expect(model.runPreferencesForSubmission.sandboxPolicy.protocolValue["networkAccess"]
			as? Bool == false)
		#expect(model.serviceTierForSubmission == "flex")

		let clearedTier = try #require(RunConfigurationDefaultsUpdate(
			effectiveConfig: ["service_tier": NSNull()],
			editedKeys: ["service_tier"]
		))
		#expect(clearedTier.keys == [.serviceTier])
		_ = PreferenceReducer.reduce(
			&model,
			.preferences(.configurationDefaultsApplied(
				context(model),
				clearedTier
			))
		)
		#expect(model.preferences.runPreferences.configurationDefaults == nil)
		#expect(model.serviceTierForSubmission == "default")
	}

	private func fixture() -> WorkspaceModel
	{
		WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: nil
		))
	}

	private func context(_ model: WorkspaceModel) -> OperationContext
	{
		OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID()
		)
	}
}
