import Foundation

extension AppServer
{
	/// A decoded response belongs to the connection that requested it.
	func decodeProtocolPayload<Value: Sendable>(
		_ payload: ProtocolJSONPayload,
		generation: UUID,
		priority: TaskPriority,
		decode: @escaping @Sendable (ProtocolJSONPayload) throws -> Value
	) async throws -> Value
	{
		try validateDecodingConnection(generation)
		let decoding = Task.detached(priority: priority)
		{
			try decode(payload)
		}
		let value = try await withTaskCancellationHandler
		{
			try await decoding.value
		}
		onCancel:
		{
			decoding.cancel()
		}
		try validateDecodingConnection(generation)
		return value
	}

	private func validateDecodingConnection(_ generation: UUID) throws
	{
		try Task.checkCancellation()
		guard generation == connectionGeneration
		else
		{
			throw AppServerError.disconnected
		}
	}
}
