import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct AppServerPaginationTests
{

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

}
