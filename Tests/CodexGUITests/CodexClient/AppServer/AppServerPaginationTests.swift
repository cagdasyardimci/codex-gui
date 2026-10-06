import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct AppServerPaginationTests
{
	@Test(arguments: ["model/list", "thread/list"])
	func listingRejectsRepeatedCursorBeforeRequestingAnotherPage(_ method: String) async throws
	{
		let fixture = try AppServerListHistoryFixture.make()
		defer
		{
			fixture.close()
		}
		try await fixture.server.connect()
		do
		{
			if method == "model/list"
			{
				_ = try await fixture.server.models()
			}
			else
			{
				_ = try await fixture.server.threads(for: fixture.directory)
			}
			Issue.record("A repeated list cursor was accepted for \(method).")
		}
		catch AppServerError.protocolError(let message)
		{
			let expected = method == "model/list"
				? "Codex repeated the model list cursor."
				: "Codex repeated the conversation list cursor."
			#expect(message == expected)
		}
		let requests = fixture.messages().filter
		{
			$0["method"] as? String == method
		}
		#expect(requests.count == 2)
		let first = try #require(requests.first?["params"] as? [String: Any])
		let second = try #require(requests.last?["params"] as? [String: Any])
		#expect(first["cursor"] == nil)
		#expect(second["cursor"] as? String == "repeated-list-cursor")
	}
}
