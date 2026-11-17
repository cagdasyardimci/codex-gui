import Foundation

extension WorkspaceEffectRunner
{
	func performReadAloud(_ operation: ReadAloudOperation) async throws -> WorkspaceAction
	{
		switch operation
		{
		case .probe(let context):
			guard let path = context.workspace.canonicalCheckoutPath
			else
			{
				return .readAloud(.availabilityReceived(
					context,
					false
				))
			}
			return .readAloud(.availabilityReceived(
				context,
				(try? await service.readAloudAvailable(in: URL(fileURLWithPath: path))) == true
			))
		case .play(let request):
			let ownsCurrentTransport = !hasObservedSubscription ||
				(subscription?.workspace == request.context.workspace && subscription?
					.generation == request.context.generation)
			guard ownsCurrentTransport
			else
			{
				throw AppServerError.disconnected
			}
			try await readAloudRuntime.play(request)
			{
				[weak self] in
				self?.deliver(
					.readAloud(.speaking(request)),
					{
					}
				)
			}
			return .readAloud(.finished(
				request,
				nil
			))
		}
	}
}
