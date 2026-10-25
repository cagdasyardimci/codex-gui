import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct RemoteAccessReducerTests
{
	private let now = Date(timeIntervalSince1970: 1000)

	private func fixture() -> WorkspaceModel
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/remote-access"
		))
		model.connection.isConnected = true
		model.remoteAccess.status = status(.connected)
		return model
	}

	private func context(_ model: WorkspaceModel) -> OperationContext
	{
		OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID()
		)
	}

	private func status(
		_ connection: RemoteControlStatus.Connection,
		environment: String = "environment"
	) -> RemoteControlStatus
	{
		RemoteControlStatus(
			status: connection,
			serverName: "Test Mac",
			installationId: "installation",
			environmentId: environment
		)
	}

	private func pairing(expiresAt: Int64 = 1010) -> RemoteControlPairing
	{
		RemoteControlPairing(
			pairingCode: "secret",
			manualPairingCode: "ABCD-EFGH",
			environmentId: "environment",
			expiresAt: expiresAt
		)
	}

	private func request(
		_ command: RemoteAccessCommand,
		model: inout WorkspaceModel
	) throws -> RemoteAccessOperation
	{
		let result = RemoteAccessReducer.reduce(
			&model,
			.remoteAccess(.requested(
				context(model),
				command,
				now
			))
		)
		#expect(result.effects.count == 1)
		return try #require(model.remoteAccess.pending)
	}

	@Test func enabledSourceRestoresAccessOnEachConnectionUntilDisabled() throws
	{
		var model = fixture()
		model.lifecycle.owner = .source(sessionID: model.identity.sessionID)
		model.remoteAccess.desiredEnabled = true
		model.remoteAccess.status = nil
		let firstContext = context(model)
		model.lifecycle.bootstrapRequestID = firstContext.requestID
		let first = RemoteAccessReducer.reduce(
			&model,
			.connection(.connectionFinished(
				firstContext,
				.succeeded(())
			))
		)
		let firstOperation = try #require(model.remoteAccess.pending)
		#expect(firstOperation.command == .setEnabled(true))
		#expect(first.effects.count == 1)

		model.connection.isConnected = false
		_ = RemoteAccessReducer.reduce(
			&model,
			.connection(.connectRequested(firstContext))
		)
		#expect(model.remoteAccess.desiredEnabled)
		#expect(model.remoteAccess.pending == nil)

		model.connection.isConnected = true
		model.connection.generation += 1
		let secondContext = context(model)
		model.lifecycle.bootstrapRequestID = secondContext.requestID
		let second = RemoteAccessReducer.reduce(
			&model,
			.connection(.connectionFinished(
				secondContext,
				.succeeded(())
			))
		)
		#expect(second.effects.count == 1)
		#expect(model.remoteAccess.pending?.command == .setEnabled(true))

		model.remoteAccess.pending = nil
		let disable = RemoteAccessReducer.reduce(
			&model,
			.remoteAccess(.requested(
				secondContext,
				.setEnabled(false),
				now
			))
		)
		#expect(!model.remoteAccess.desiredEnabled)
		#expect(disable.effects.contains
		{
			if case .persistPreference(let write) = $0,
				case .remoteAccess(false) = write.value
			{
				return true
			}
			return false
		})
		model.remoteAccess.pending = nil
		let third = RemoteAccessReducer.reduce(
			&model,
			.connection(.connectionFinished(
				context(model),
				.succeeded(())
			))
		)
		#expect(third.effects.isEmpty)
	}

	@Test func autoEnableFollowsTheCurrentCheckoutAfterBootstrap() throws
	{
		var model = fixture()
		model.lifecycle.owner = .source(sessionID: model.identity.sessionID)
		model.remoteAccess.desiredEnabled = true
		let original = context(model)
		model.lifecycle.bootstrapRequestID = original.requestID
		model.identity = WorkspaceIdentity(
			sessionID: model.identity.sessionID,
			canonicalCheckoutPath: "/tmp/other-checkout"
		)
		_ = RemoteAccessReducer.reduce(
			&model,
			.connection(.connectionFinished(
				original,
				.succeeded(())
			))
		)
		let operation = try #require(model.remoteAccess.pending)
		#expect(operation.context.workspace == model.identity)
		_ = RemoteAccessReducer.reduce(
			&model,
			.remoteAccess(.finished(
				operation,
				.succeeded(RemoteAccessUpdate(status: status(.connected))),
				now
			))
		)
		#expect(model.remoteAccess.pending == nil)
		#expect(model.remoteAccess.status?.status == .connected)
		model.lifecycle.bootstrapRequestID = nil
		let replay = RemoteAccessReducer.reduce(
			&model,
			.connection(.connectionFinished(
				original,
				.succeeded(())
			))
		)
		#expect(replay.effects.isEmpty)
	}

	@Test func newerNotificationsAndEnvironmentChangesRejectStaleReadResults() throws
	{
		var model = fixture()
		let operation = try request(
			.refresh,
			model: &model
		)
		_ = RemoteAccessReducer.reduce(
			&model,
			.remoteAccess(.statusObserved(
				context(model),
				status(
					.connected,
					environment: "new"
				)
			))
		)
		_ = RemoteAccessReducer.reduce(
			&model,
			.remoteAccess(.finished(
				operation,
				.succeeded(RemoteAccessUpdate(
					status: status(.connecting),
					clients: [client("old-device")],
					environmentID: "environment",
					error: "Old host failure"
				)),
				now
			))
		)
		#expect(model.remoteAccess.status?.status == .connected)
		#expect(model.remoteAccess.status?.environmentId == "new")
		#expect(model.remoteAccess.clients.isEmpty)
		#expect(model.remoteAccess.error == nil)
		#expect(model.remoteAccess.pending == nil)
	}

	@Test func expiryAndClosingPairingPreventLateCodesFromReappearing() throws
	{
		var model = fixture()
		model.remoteAccess.pairing = pairing(expiresAt: 1000)
		_ = RemoteAccessReducer.reduce(
			&model,
			.remoteAccess(.requested(
				context(model),
				.expirePairing,
				now
			))
		)
		#expect(model.remoteAccess.pairing == nil)
		let operation = try request(
			.pair,
			model: &model
		)
		_ = RemoteAccessReducer.reduce(
			&model,
			.remoteAccess(.requested(
				context(model),
				.clearPairing,
				now
			))
		)
		_ = RemoteAccessReducer.reduce(
			&model,
			.remoteAccess(.finished(
				operation,
				.succeeded(RemoteAccessUpdate(pairing: pairing())),
				now
			))
		)
		#expect(model.remoteAccess.pairing == nil)
		#expect(model.remoteAccess.pending == nil)
	}

	@Test func claimedPairingClearsCodeAndOldConnectionsCannotRestoreIt() throws
	{
		var model = fixture()
		model.remoteAccess.pairing = pairing()
		let operation = try request(
			.refresh,
			model: &model
		)
		_ = RemoteAccessReducer.reduce(
			&model,
			.remoteAccess(.finished(
				operation,
				.succeeded(RemoteAccessUpdate(pairingClaimed: true)),
				now
			))
		)
		#expect(model.remoteAccess.pairing == nil)
		model.remoteAccess.pairing = pairing()
		let pending = try request(
			.pair,
			model: &model
		)
		model.connection.generation += 1
		_ = RemoteAccessReducer.reduce(
			&model,
			.remoteAccess(.finished(
				pending,
				.succeeded(RemoteAccessUpdate(pairing: pairing())),
				now
			))
		)
		#expect(model.remoteAccess.pairing == nil)
	}

	@Test func revocationRequiresTheDisplayedEnvironmentAndRemovesOnlyItsDevice() throws
	{
		var model = fixture()
		model.remoteAccess.clients = [client("one"), client("two")]
		let rejected = RemoteAccessReducer.reduce(
			&model,
			.remoteAccess(.requested(
				context(model),
				.revoke(
					environmentID: "foreign",
					clientID: "one"
				),
				now
			))
		)
		#expect(rejected.effects.isEmpty)
		let operation = try request(
			.revoke(
				environmentID: "environment",
				clientID: "one"
			),
			model: &model
		)
		_ = RemoteAccessReducer.reduce(
			&model,
			.remoteAccess(.finished(
				operation,
				.succeeded(RemoteAccessUpdate()),
				now
			))
		)
		#expect(model.remoteAccess.clients.map(\.clientId) == ["two"])
	}

	@Test func disablingAccessPreemptsPairingAndRejectsItsLateResponse() throws
	{
		var model = fixture()
		let pairingOperation = try request(
			.pair,
			model: &model
		)
		let reduction = RemoteAccessReducer.reduce(
			&model,
			.remoteAccess(.requested(
				context(model),
				.setEnabled(false),
				now
			))
		)
		#expect(reduction.effects.count == 2)
		let disable = try #require(model.remoteAccess.pending)
		#expect(disable.command == .setEnabled(false))
		let first = try #require(reduction.effects.first)
		let last = try #require(reduction.effects.last)
		guard case .cancel(let cancelled) = first,
				case .remoteAccess(let started) = last
		else
		{
			Issue.record("Expected pairing cancellation before disabling remote access")
			return
		}
		#expect(cancelled == pairingOperation.context)
		#expect(started == disable)
		_ = RemoteAccessReducer.reduce(
			&model,
			.remoteAccess(.finished(
				pairingOperation,
				.succeeded(RemoteAccessUpdate(pairing: pairing())),
				now
			))
		)
		#expect(model.remoteAccess.pending == disable)
		#expect(model.remoteAccess.pairing == nil)
		_ = RemoteAccessReducer.reduce(
			&model,
			.remoteAccess(.finished(
				disable,
				.succeeded(RemoteAccessUpdate(status: status(.disabled))),
				now
			))
		)
		#expect(model.remoteAccess.status?.status == .disabled)
	}

	private func client(_ id: String) -> RemoteControlClient
	{
		RemoteControlClient(
			clientId: id,
			displayName: "Phone",
			deviceType: "phone",
			platform: "ios",
			osVersion: nil,
			deviceModel: nil,
			appVersion: nil,
			lastSeenAt: nil
		)
	}
}
