import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct AppServerConcurrentThreadTests
{
	@Test func oneConnectionKeepsInterleavedTurnsAndControlOwnershipIndependent() async throws
	{
		let fixture = try InterleavedThreadTransportFixture()
		defer
		{
			try? FileManager.default.removeItem(at: fixture.directory)
		}
		let server = AppServer(
			executableOverride: fixture.executable,
			requestTimeout: .seconds(3)
		)
		defer
		{
			server.disconnect()
		}
		var deltas: [String: [String]] = [:]
		var started: [String: String] = [:]
		var completed: [String: String] = [:]
		var approvals: [PendingInteraction] = []
		var resolutions: [String] = []
		var errors: [String] = []
		server.onEvent =
		{
			event in
			switch event
			{
			case .agentMessageDelta(
				let owner,
				let turnID,
				let itemID,
				let text
			):
				#expect(turnID == owner + "-turn")
				#expect(itemID == "shared-item")
				deltas[owner, default: []].append(text)
			case .turnStarted(
				let owner,
				let turn
			):
				started[owner] = turn.id
			case .turnCompleted(
				let owner,
				let turn
			):
				#expect(turn.id == owner + "-turn")
				completed[owner] = turn.status
			case .interaction(let interaction):
				approvals.append(interaction)
			case .interactionResolved(
				let owner,
				_
			):
				resolutions.append(owner)
			case .error(
				let owner,
				let turnID,
				let message,
				let willRetry
			):
				#expect(turnID == "beta-turn")
				#expect(message == "synthetic beta failure")
				#expect(!willRetry)
				errors.append(owner)
			default:
				break
			}
		}
		try await server.connect()
		// Raw thread requests avoid the separate automatic title generation lifecycle.
		for owner in ["alpha", "beta"]
		{
			_ = try await server.request(
				"thread/start",
				params: ["owner": owner, "cwd": fixture.directory.path]
			)
		}
		async let alphaStart = server.startTurn(
			threadId: "alpha",
			text: "Alpha task"
		)
		async let betaStart = server.startTurn(
			threadId: "beta",
			text: "Beta task"
		)
		let (alpha, beta) = try await (alphaStart, betaStart)
		#expect(alpha.id == "alpha-turn")
		#expect(beta.id == "beta-turn")
		try await waitUntil
		{
			approvals.count == 2 && deltas["alpha"]?.count == 2
		}
		#expect(started == ["alpha": alpha.id, "beta": beta.id])
		#expect(deltas["alpha"] == ["A1\u{2028}", "A2"])
		#expect(deltas["beta"] == ["B1", "B2"])
		let alphaApproval = try #require(approvals.first
		{
			$0.threadId == "alpha"
		})
		let betaApproval = try #require(approvals.first
		{
			$0.threadId == "beta"
		})
		#expect(alphaApproval.id != betaApproval.id)
		#expect(alphaApproval.turnId == alpha.id)
		#expect(betaApproval.turnId == beta.id)
		try server.respond(
			to: alphaApproval.id,
			with: .approval(.accept)
		)
		try await waitUntil
		{
			resolutions == ["alpha"]
		}
		#expect(completed.isEmpty)
		do
		{
			_ = try await server.steerTurn(
				threadId: "alpha",
				expectedTurnId: beta.id,
				text: "Stale ownership"
			)
			Issue.record("Steering accepted another thread's turn identity")
		}
		catch let error as AppServerError
		{
			guard case .requestRejected(let message) = error
			else
			{
				throw error
			}
			#expect(message == "wrong active turn")
		}
		#expect(try await server.steerTurn(
			threadId: "beta",
			expectedTurnId: beta.id,
			text: "Continue beta"
		) == beta.id)
		try await server.interrupt(
			threadId: "alpha",
			turnId: alpha.id
		)
		try await waitUntil
		{
			deltas["beta"]?.last == "after-alpha-stop"
		}
		#expect(completed == ["alpha": "interrupted"])
		#expect(resolutions == ["alpha"])
		#expect(errors.isEmpty)
		try server.respond(
			to: betaApproval.id,
			with: .approval(.decline)
		)
		try await waitUntil
		{
			completed["beta"] == "failed"
		}
		#expect(completed == ["alpha": "interrupted", "beta": "failed"])
		#expect(resolutions == ["alpha", "beta"])
		#expect(errors == ["beta"])
		#expect(deltas["alpha"] == ["A1\u{2028}", "A2"])
		#expect(deltas["beta"] == ["B1", "B2", "steered", "after-alpha-stop"])
		let requests = try fixture.requests()
		#expect(requests.filter
		{
			$0["method"] as? String == "initialize"
		}.count == 1)
		let interrupts = requests.filter
		{
			$0["method"] as? String == "turn/interrupt"
		}
		#expect(interrupts.count == 1)
		let interrupt = try #require(interrupts.first?["params"] as? [String: Any])
		#expect(interrupt["threadId"] as? String == "alpha")
		#expect(interrupt["turnId"] as? String == alpha.id)
	}

	private func waitUntil(_ predicate: () -> Bool) async throws
	{
		for _ in 0 ..< 150
		{
			if predicate()
			{
				return
			}
			try await Task.sleep(for: .milliseconds(10))
		}
		try #require(
			predicate(),
			"Synthetic transport did not reach the expected event barrier"
		)
	}
}
