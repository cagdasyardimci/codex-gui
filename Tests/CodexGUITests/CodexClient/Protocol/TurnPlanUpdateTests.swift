import Foundation
import Testing

@testable import CodexGUI

struct TurnPlanUpdateTests
{
	@Test func planUpdateKeepsBackendStepStatusAndTurnIdentity() throws
	{
		let update = try #require(
			TurnPlanUpdate(json: [
				"threadId": "thread-2",
				"turnId": "turn-7",
				"explanation": "Checking the tests",
				"plan": [
					["step": "Inspect failures", "status": "completed"],
					["step": "Fix parser", "status": "inProgress"],
					["step": "Run checks", "status": "pending"],
				],
			])
		)

		#expect(update.threadId == "thread-2")
		#expect(update.turnId == "turn-7")
		#expect(update.explanation == "Checking the tests")
		#expect(update.plan.map(\.status) == [.completed, .inProgress, .pending])
		#expect(update.plan.map(\.step) == ["Inspect failures", "Fix parser", "Run checks"])
		#expect(
			TurnPlanUpdate(json: [
				"threadId": "thread-2",
				"turnId": "turn-7",
				"plan": [["step": "Unknown", "status": "almostDone"]],
			]) == nil
		)
	}

}
