import Foundation

@MainActor
enum RemoteAccessReducer
{
	static let reducer = WorkspaceReducer(reduce: reduce)

	static func reduce(
		_ model: inout WorkspaceModel,
		_ action: WorkspaceAction
	) -> WorkspaceReduction
	{
		if case .connection(let connectionAction) = action
		{
			if !model.connection.isConnected
			{
				model.remoteAccess = RemoteAccessModel(
					desiredEnabled: model.remoteAccess.desiredEnabled
				)
			}
			else if let pending = model.remoteAccess.pending, !valid(
				pending.context,
				model
			)
			{
				model.remoteAccess.pending = nil
				model.remoteAccess.pairing = nil
			}
			if case .connectionFinished(
				let context,
				.succeeded
			) = connectionAction,
				case .source = model.lifecycle.owner,
				context.requestID == model.lifecycle.bootstrapRequestID,
				context.workspace.sessionID == model.identity.sessionID,
				context.generation == model.connection.generation,
				model.remoteAccess.desiredEnabled,
				model.connection.isConnected,
				model.remoteAccess.pending == nil
			{
				let operation = RemoteAccessOperation(
					context: OperationContext(
						workspace: model.identity,
						generation: context.generation,
						requestID: context.requestID
					),
					command: .setEnabled(true),
					statusRevision: model.remoteAccess.statusRevision
				)
				model.remoteAccess.pending = operation
				return WorkspaceReduction(effects: [.remoteAccess(operation)])
			}
		}
		var reduction = WorkspaceReduction()
		guard case .remoteAccess(let action) = action
		else
		{
			return WorkspaceReduction()
		}
		switch action
		{
		case .requested(
			let context,
			let command,
			let now
		):
			guard valid(
				context,
				model
			), model.connection.isConnected
			else
			{
				return WorkspaceReduction()
			}
			if command == .setEnabled(false), let pending = model.remoteAccess.pending,
				pending.command == .refresh || pending.command == .pair
			{
				model.remoteAccess.pending = nil
				let next = reduce(
					&model,
					.remoteAccess(.requested(
						context,
						command,
						now
					))
				)
				return WorkspaceReduction(effects: [.cancel(pending.context)] + next.effects)
			}
			if command == .expirePairing || command == .clearPairing
			{
				if command == .clearPairing || model.remoteAccess.pairing?.isValid(at: now) == false
				{
					model.remoteAccess.pairing = nil
					if command == .clearPairing, let pending = model.remoteAccess.pending,
						pending.command == .pair
					{
						model.remoteAccess.pending = nil
						return WorkspaceReduction(effects: [.cancel(pending.context)])
					}
				}
				return WorkspaceReduction()
			}
			guard model.remoteAccess.pending == nil
			else
			{
				return WorkspaceReduction()
			}
			if command == .pair
			{
				guard model.remoteAccess.canPair
				else
				{
					return WorkspaceReduction()
				}
				model.remoteAccess.pairing = nil
			}
			if case .revoke(
				let environmentID,
				let clientID
			) = command
			{
				guard model.remoteAccess.status?.environmentId == environmentID,
						model.remoteAccess.clients.contains(where:
						{
							$0.clientId == clientID
						})
				else
				{
					return WorkspaceReduction()
				}
			}
			if command == .setEnabled(false)
			{
				model.remoteAccess.pairing = nil
			}
			let operation = RemoteAccessOperation(
				context: context,
				command: command,
				statusRevision: model.remoteAccess.statusRevision,
				pairing: model.remoteAccess.pairing
			)
			model.remoteAccess.pending = operation
			model.remoteAccess.error = nil
			var effects: [WorkspaceEffect] = []
			if case .setEnabled(let enabled) = command,
				case .source = model.lifecycle.owner
			{
				model.remoteAccess.desiredEnabled = enabled
				effects.append(.persistPreference(PreferenceWrite(
					context: context,
					value: .remoteAccess(enabled)
				)))
			}
			effects.append(.remoteAccess(operation))
			return WorkspaceReduction(effects: effects)
		case .finished(
			let operation,
			let result,
			let now
		):
			guard valid(
				operation.context,
				model
			), model.remoteAccess.pending == operation
			else
			{
				return WorkspaceReduction()
			}
			model.remoteAccess.pending = nil
			reduction.effects.append(.readBackendDiagnostics(operation.context))
			switch result
			{
			case .failed(let failure):
				if operation.statusRevision == model.remoteAccess.statusRevision
				{
					model.remoteAccess.error = failure.message
				}
			case .succeeded(let update):
				if case .revoke(
					let environmentID,
					let clientID
				) = operation.command,
					environmentID == model.remoteAccess.status?.environmentId
				{
					model.remoteAccess.clients.removeAll
					{
						$0.clientId == clientID
					}
				}
				if update.pairingClaimed, model.remoteAccess.pairing == operation.pairing
				{
					model.remoteAccess.pairing = nil
				}
				if let status = update.status,
					operation.statusRevision == model.remoteAccess.statusRevision
				{
					apply(
						status,
						model: &model
					)
				}
				if operation.statusRevision == model.remoteAccess.statusRevision
				{
					model.remoteAccess.error = update.error
					model.remoteAccess.connectionFailure = model.remoteAccess.status?
						.status == .errored
						? update.connectionFailure : nil
				}
				if let pairing = update.pairing, pairing.isValid(at: now),
					pairing.environmentId == model.remoteAccess.status?.environmentId,
					model.remoteAccess.status?.status == .connected
				{
					model.remoteAccess.pairing = pairing
				}
				if let clients = update.clients,
					update.environmentID == model.remoteAccess.status?.environmentId
				{
					model.remoteAccess.clients = clients
				}
			}
		case .statusObserved(
			let context,
			let status
		):
			guard valid(
				context,
				model
			)
			else
			{
				return WorkspaceReduction()
			}
			model.remoteAccess.statusRevision += 1
			apply(
				status,
				model: &model
			)
		}
		return reduction
	}

	private static func valid(
		_ context: OperationContext,
		_ model: WorkspaceModel
	) -> Bool
	{
		context.belongsTo(
			workspace: model.identity,
			generation: model.connection.generation
		)
	}

	private static func apply(
		_ status: RemoteControlStatus,
		model: inout WorkspaceModel
	)
	{
		if status.environmentId != model.remoteAccess.status?.environmentId
		{
			model.remoteAccess.clients = []
			model.remoteAccess.pairing = nil
			model.remoteAccess.error = nil
			model.remoteAccess.connectionFailure = nil
		}
		if status.status != .errored
		{
			model.remoteAccess.connectionFailure = nil
		}
		if status.status != .connected
		{
			model.remoteAccess.pairing = nil
		}
		model.remoteAccess.status = status
	}
}
