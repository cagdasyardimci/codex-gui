import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct AppServerHistoryLoadingTests
{
	@Test func historyPagePreservesCursorRequestOrderAndUnicodeContent() async throws
	{
		let fixture = try await AppServerListHistoryFixture.make()
		defer
		{
			fixture.close()
		}
		try await fixture.server.connect()
		let page = try await fixture.server.loadTurns(
			threadId: "thread",
			cursor: "older-cursor"
		)
		#expect(page.turns.map(\.id) == ["earlier", "latest"])
		#expect(page.nextCursor == "next-cursor")
		let text = try #require(page.turns.last?.items.first?.text)
		#expect(text.utf8.elementsEqual("é e\u{0301}🧪\u{2028}終\nsecond".utf8))
		let request = try #require(fixture.messages().first
		{
			$0["method"] as? String == "thread/turns/list"
		})
		let params = try #require(request["params"] as? [String: Any])
		#expect(params["threadId"] as? String == "thread")
		#expect(params["cursor"] as? String == "older-cursor")
		#expect(params["limit"] as? Int == 25)
		#expect(params["sortDirection"] as? String == "desc")
		#expect(params["itemsView"] as? String == "full")
	}

	@Test func initialHistoryPageLoadsTwentyFiveFullTurns() async throws
	{
		let fixture = try await AppServerListHistoryFixture.make()
		defer
		{
			fixture.close()
		}
		try await fixture.server.connect()
		_ = try await fixture.server.loadTurns(threadId: "thread")
		let request = try #require(fixture.messages().first
		{
			$0["method"] as? String == "thread/turns/list"
		})
		let params = try #require(request["params"] as? [String: Any])
		#expect(params["limit"] as? Int == 25)
		#expect(params["cursor"] == nil)
		#expect(params["itemsView"] as? String == "full")
	}

	@Test func turnReferencePageOmitsContentAndCoversTheRailViewport() async throws
	{
		let fixture = try await AppServerListHistoryFixture.make()
		defer
		{
			fixture.close()
		}
		try await fixture.server.connect()
		let service: any CodexService = fixture.server
		let page = try await service.loadTurnReferences(
			threadId: "thread",
			cursor: nil
		)
		#expect(page.references.map(\.id) == ["earlier", "latest"])
		#expect(page.references.map(\.status) == ["completed", "failed"])
		#expect(page.nextCursor == "older-reference-cursor")
		let earlier = try #require(page.references.first)
		#expect(earlier.startedAt == nil)
		#expect(earlier.completedAt == nil)
		#expect(earlier.durationMs == nil)
		#expect(earlier.error == nil)
		let latest = try #require(page.references.last)
		#expect(latest.startedAt == Date(timeIntervalSince1970: 100.25))
		#expect(latest.completedAt == Date(timeIntervalSince1970: 101.5))
		#expect(latest.durationMs == 1250)
		#expect(latest.error == "Recorded reference failure")
		let request = try #require(fixture.messages().first
		{
			$0["method"] as? String == "thread/turns/list"
		})
		let params = try #require(request["params"] as? [String: Any])
		#expect(params["limit"] as? Int == 100)
		#expect(params["cursor"] == nil)
		#expect(params["sortDirection"] as? String == "desc")
		#expect(params["itemsView"] as? String == "notLoaded")
	}

	@Test func turnReferencePageRejectsRowsWithoutAnIDInsteadOfDroppingThem() async throws
	{
		let fixture = try await AppServerListHistoryFixture.make(invalidReferenceID: true)
		defer
		{
			fixture.close()
		}
		try await fixture.server.connect()
		do
		{
			_ = try await fixture.server.loadTurnReferences(
				threadId: "thread",
				cursor: nil
			)
			Issue.record("A malformed reference row must not become an incomplete navigation page")
		}
		catch AppServerError.protocolError(let message)
		{
			#expect(message == "Codex returned a turn reference without an ID.")
		}
		#expect(fixture.messages().filter
		{
			$0["method"] as? String == "thread/turns/list"
		}.count == 1)
	}

	@Test func hoverPreviewReadsOnlyBoundaryPagesAndMarksPartialContent() async throws
	{
		let fixture = try await AppServerListHistoryFixture.make()
		defer
		{
			fixture.close()
		}
		try await fixture.server.connect()
		let service: any CodexService = fixture.server
		let turn = try await service.loadTurnPreviewContents(
			threadId: "thread",
			reference: ConversationTurnReference(
				id: "picked",
				status: "completed"
			)
		)
		#expect(!turn.itemsAreComplete)
		#expect(turn.items.map(\.id) == ["request", "reply"])
		let requests = fixture.messages().filter
		{
			$0["method"] as? String == "thread/items/list"
		}
		#expect(requests.count == 2)
		let parameters = try requests.map
		{
			try #require($0["params"] as? [String: Any])
		}
		#expect(parameters.compactMap
		{
			$0["sortDirection"] as? String
		} == ["asc", "desc"])
		#expect(parameters
			.allSatisfy
			{
				$0["cursor"] == nil && $0["turnId"] as? String == "picked"
			})
	}

	@Test func loadingAReferencedTurnFetchesOnlyItsItemsAndContinuesItsCursor() async throws
	{
		let fixture = try await AppServerListHistoryFixture.make()
		defer
		{
			fixture.close()
		}
		try await fixture.server.connect()
		let turn = try await fixture.server.loadTurnContents(
			threadId: "thread",
			reference: ConversationTurnReference(
				id: "picked",
				status: "completed"
			)
		)
		#expect(turn.id == "picked")
		#expect(turn.items.map(\.id) == ["request", "reply"])
		let requests = fixture.messages().filter
		{
			$0["method"] as? String == "thread/items/list"
		}
		#expect(requests.count == 2)
		let parameters = try requests.map
		{
			try #require($0["params"] as? [String: Any])
		}
		#expect(parameters
			.allSatisfy
			{
				$0["threadId"] as? String == "thread" && $0["turnId"] as? String == "picked" &&
					$0["sortDirection"] as? String == "asc"
			})
		#expect(parameters.first?["cursor"] == nil)
		#expect(parameters.last?["cursor"] as? String == "next-items")
		#expect(!fixture.methods().contains("thread/turns/list"))
	}

	@Test func loadingAReferenceRejectsItemsFromAnotherTurn() async throws
	{
		let fixture = try await AppServerListHistoryFixture.make()
		defer
		{
			fixture.close()
		}
		try await fixture.server.connect()
		do
		{
			_ = try await fixture.server.loadTurnContents(
				threadId: "thread",
				reference: ConversationTurnReference(
					id: "foreign",
					status: "completed"
				)
			)
			Issue.record("An item from another turn was accepted")
		}
		catch AppServerError.protocolError
		{
		}
	}
}
