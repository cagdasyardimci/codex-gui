import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct AppServerPaginationTests
{
	@Test func globalThreadListingOmitsCheckoutFilterAndKeepsCrossProjectPages() async throws
	{
		let fixture = try await AppServerListHistoryFixture.make(overlappingThreadPages: true)
		defer
		{
			fixture.close()
		}
		try await fixture.server.connect()
		let threads = try await fixture.server.allThreads(archived: false)
		#expect(threads.map(\.id) == ["first", "shared", "last"])
		#expect(Set(threads.map(\.cwd)).count == 2)
		let requests = fixture.messages().filter
		{
			$0["method"] as? String == "thread/list"
		}
		#expect(requests.count == 2)
		for request in requests
		{
			let params = try #require(request["params"] as? [String: Any])
			#expect(params["cwd"] == nil)
			#expect(params["archived"] as? Bool == false)
		}
	}

	@Test(arguments: [false, true])
	func threadListingKeepsOneRowPerIDAcrossOverlappingPages(archived: Bool) async throws
	{
		let fixture = try await AppServerListHistoryFixture.make(overlappingThreadPages: true)
		defer
		{
			fixture.close()
		}
		try await fixture.server.connect()
		let threads = try await fixture.server.threads(
			for: fixture.directory,
			archived: archived
		)
		#expect(threads.map(\.id) == ["first", "shared", "last"])
		#expect(threads.map(\.name) == ["Same title", "Same title", "Same title"])
		#expect(threads.map(\.preview) == ["page-1", "page-1", "page-2"])
		let requests = fixture.messages().filter
		{
			$0["method"] as? String == "thread/list"
		}
		#expect(requests.count == 2)
		for request in requests
		{
			let parameters = try #require(request["params"] as? [String: Any])
			#expect(parameters["archived"] as? Bool == archived)
		}
	}

	@Test(
		arguments: [false, true],
		[1, 2]
	)
	func threadListingValidatesDuplicateRowsBeforeRemovingThem(
		archived: Bool,
		invalidPage: Int
	) async throws
	{
		let fixture = try await AppServerListHistoryFixture.make(
			overlappingThreadPages: true,
			invalidDuplicatePage: invalidPage
		)
		defer
		{
			fixture.close()
		}
		try await fixture.server.connect()
		do
		{
			_ = try await fixture.server.threads(
				for: fixture.directory,
				archived: archived
			)
			Issue.record("A duplicate thread from another checkout was accepted")
		}
		catch AppServerError.protocolError(let message)
		{
			#expect(message == "Codex returned a conversation from another checkout.")
		}
		#expect(fixture.messages().filter
		{
			$0["method"] as? String == "thread/list"
		}.count == invalidPage)
	}

	@Test(arguments: ["model/list", "thread/list"])
	func listingRejectsRepeatedCursorBeforeRequestingAnotherPage(_ method: String) async throws
	{
		let fixture = try await AppServerListHistoryFixture.make()
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
