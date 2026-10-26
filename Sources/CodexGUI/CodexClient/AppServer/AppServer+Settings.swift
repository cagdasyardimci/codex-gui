import Foundation

extension AppServer
{
	/// Settings use the same framed transport, deadlines and uncertain-write handling as chats.
	func settingsRequest(
		_ method: String,
		params: [String: Any]
	) async throws -> [String: Any]
	{
		try await request(
			method,
			params: params
		)
	}
}
