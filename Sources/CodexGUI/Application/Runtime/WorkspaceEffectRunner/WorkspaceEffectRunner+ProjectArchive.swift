import Foundation

extension WorkspaceEffectRunner
{
	func archiveProjectChats(_ operation: ProjectArchiveOperation) async -> ProjectArchiveResult
	{
		var archivedIDs: [String] = []
		do
		{
			let threads = try await service.threads(
				for: operation.project,
				archived: false
			)
			// Validate the entire list before making the first mutation.
			for thread in threads
			{
				try CheckoutIdentity.validate(
					cwd: thread.cwd,
					expectedDirectory: operation.project
				)
				guard thread.status != "active"
				else
				{
					throw AppServerError
						.protocolError("A project chat is still active. Stop it before archiving.")
				}
			}
			for thread in threads
			{
				try Task.checkCancellation()
				let detail = try await service.readThread(id: thread.id)
				guard detail.summary.id == thread.id
				else
				{
					throw AppServerError
						.protocolError("The backend returned a different conversation.")
				}
				try CheckoutIdentity.validate(
					cwd: detail.summary.cwd,
					expectedDirectory: operation.project
				)
				guard detail.summary.status != "active",
						!detail.turns.contains(where:
						{
							$0.status == "inProgress"
						})
				else
				{
					throw AppServerError
						.protocolError("A project chat is still active. Stop it before archiving.")
				}
				try Task.checkCancellation()
				try await service.archiveThread(id: thread.id)
				archivedIDs.append(thread.id)
			}
			return ProjectArchiveResult(
				archivedThreadIDs: archivedIDs,
				failure: nil
			)
		}
		catch
		{
			return ProjectArchiveResult(
				archivedThreadIDs: archivedIDs,
				failure: OperationFailure(
					message: error.localizedDescription,
					outcomeIsUncertain: true
				)
			)
		}
	}
}
