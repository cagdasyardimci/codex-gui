import Foundation

/// Executes only captured Git/persistence operations. Store reservations and AppKit stay separate.
struct WorkspaceLifecycleGitRunner
{
	let manager: GitWorktreeManager

	func perform(_ effect: WorkspaceLifecycleGitEffect) async -> WorkspaceCoordinatorAction
	{
		do
		{
			switch effect
			{
			case .recover(let request):
				let records: [TaskWorkspaceRecovery]
				if let cleanup = request.cleanup
				{
					records = try await manager.recover(preservingRemovalOf: cleanup.expected)
				}
				else
				{
					records = try await manager.recover()
				}
				return .recoveryFinished(
					request,
					.succeeded(records)
				)
			case .create(let request):
				guard let path = request.source.canonicalCheckoutPath
				else
				{
					throw TaskWorkspaceError.invalidRecord("source checkout is absent")
				}
				let workspace = try await manager.createCheckout(
					taskID: request.taskID,
					name: request.name,
					from: URL(fileURLWithPath: path)
				)
				return .creationFinished(
					request,
					.succeeded(workspace)
				)
			case .verifySelection(let request):
				return .selectionVerified(
					request,
					.succeeded(try await manager.activeCheckout(expected: request.expected))
				)
			case .remove(let request):
				return .cleanupFinished(
					request,
					.succeeded(try await manager.removeCheckout(expected: request.expected))
				)
			case .cancelCreation(
				let id,
				let expected
			):
				return .cancellationFinished(
					requestID: id,
					expected: expected,
					.succeeded(try await manager.cancelIncompleteCreation(expected: expected))
				)
			}
		}
		catch
		{
			let failure = OperationFailure(
				message: error.localizedDescription,
				outcomeIsUncertain: false
			)
			switch effect
			{
			case .recover(let request):
				return .recoveryFinished(
					request,
					.failed(failure)
				)
			case .create(let request):
				return .creationFinished(
					request,
					.failed(failure)
				)
			case .verifySelection(let request):
				return .selectionVerified(
					request,
					.failed(failure)
				)
			case .remove(let request):
				return .cleanupFinished(
					request,
					.failed(failure)
				)
			case .cancelCreation(
				let id,
				let expected
			):
				return .cancellationFinished(
					requestID: id,
					expected: expected,
					.failed(failure)
				)
			}
		}
	}
}
