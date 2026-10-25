import Foundation

extension WorkspaceEffectRunner
{
	func performRemoteAccess(_ operation: RemoteAccessOperation) async throws -> WorkspaceAction
	{
		var update = RemoteAccessUpdate()
		switch operation.command
		{
		case .refresh:
			let status = try await service.remoteControlStatus()
			update.status = status
			if status.status == .errored
			{
				update.connectionFailure = RemoteControlDiagnostics
					.failure(in: service.backendDiagnostics.stderrTail)
			}
			if let environmentID = status.environmentId
			{
				do
				{
					update.clients = try await service
						.remoteControlClients(environmentID: environmentID)
				}
				catch
				{
					update.error = BackendDiagnosticsBuffer
						.displaySafeText(error.localizedDescription)
				}
				update.environmentID = environmentID
			}
			if let pairing = operation.pairing, pairing.isValid(at: usageRuntime.now()),
				pairing.environmentId == status.environmentId
			{
				do
				{
					update.pairingClaimed = try await service.remoteControlPairingClaimed(pairing)
				}
				catch
				{
					update.error = BackendDiagnosticsBuffer
						.displaySafeText(error.localizedDescription)
				}
			}
		case .setEnabled(let enabled):
			update.status = try await service.setRemoteControlEnabled(enabled)
		case .pair:
			update.pairing = try await service.startRemoteControlPairing()
		case .revoke(
			let environmentID,
			let clientID
		):
			try await service.revokeRemoteControlClient(
				environmentID: environmentID,
				clientID: clientID
			)
			// Do not retry the mutation if a follow-up read fails.
			return .remoteAccess(.finished(
				operation,
				.succeeded(RemoteAccessUpdate(
					clients: nil,
					environmentID: environmentID
				)),
				usageRuntime.now()
			))
		case .clearPairing, .expirePairing: break
		}
		try Task.checkCancellation()
		return .remoteAccess(.finished(
			operation,
			.succeeded(update),
			usageRuntime.now()
		))
	}
}
