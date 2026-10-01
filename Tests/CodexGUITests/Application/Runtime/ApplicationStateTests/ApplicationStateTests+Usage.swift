import Foundation
import Testing

@testable import CodexGUI

extension ApplicationStateTests
{
	@Test func sparseUsageUpdatesCoalesceDuringAnActiveRead() async throws
	{
		let service = MockCodexService()
		let state = WorkspaceTestFixture(
			server: service,
			storage: makeStorage()
		)
		await state.inputs.connect()
		#expect(service.rateLimitReadCount == 1)
		service.suspendNextRateLimitRead = true
		service.emit(.rateLimitsUpdated)
		#expect(await waitUntil
		{
			service.pendingRateLimitRead != nil
		})
		service.emit(.rateLimitsUpdated)
		service.emit(.rateLimitsUpdated)
		service.finishPendingRateLimitRead(
			with: AccountRateLimitsSnapshot(json: [
				"rateLimits": ["primary": ["usedPercent": 20.0]]
			])!
		)
		#expect(await waitUntil
		{
			service.rateLimitReadCount == 3
		})
		#expect(state.currentSnapshot.usage?.rateLimits.primary?.usedPercent == 20)
		try await Task.sleep(for: .milliseconds(20))
		#expect(service.rateLimitReadCount == 3)
	}

	@Test func usageUpdateDuringSecondReadGetsOneMoreBoundedRead() async throws
	{
		let service = MockCodexService()
		let state = WorkspaceTestFixture(
			server: service,
			storage: makeStorage()
		)
		await state.inputs.connect()
		service.suspendRateLimitReadNumbers = [2, 3]
		service.emit(.rateLimitsUpdated)
		#expect(
			await waitUntil
			{
				service.rateLimitReadCount == 2
					&& service.pendingRateLimitRead != nil
			}
		)
		service.emit(.rateLimitsUpdated)
		service.finishPendingRateLimitRead(with: service.fixtureRateLimits)
		#expect(
			await waitUntil
			{
				service.rateLimitReadCount == 3
					&& service.pendingRateLimitRead != nil
			}
		)
		service.emit(.rateLimitsUpdated)
		service.finishPendingRateLimitRead(with: service.fixtureRateLimits)
		#expect(await waitUntil
		{
			service.rateLimitReadCount == 4
		})
		#expect(state.currentSnapshot.usageError == nil)
		#expect(!state.currentSnapshot.usageIsStale)
	}

	@Test func repeatedUsageInvalidationsStopAtThreeReadsAndShowStaleWarning() async throws
	{
		let service = MockCodexService()
		let state = WorkspaceTestFixture(
			server: service,
			storage: makeStorage()
		)
		await state.inputs.connect()
		service.suspendRateLimitReadNumbers = [2, 3, 4]
		service.emit(.rateLimitsUpdated)
		for readCount in 2 ... 4
		{
			#expect(
				await waitUntil
				{
					service.rateLimitReadCount == readCount
						&& service.pendingRateLimitRead != nil
				}
			)
			service.emit(.rateLimitsUpdated)
			service.finishPendingRateLimitRead(with: service.fixtureRateLimits)
		}
		#expect(await waitUntil
		{
			state.currentSnapshot.usageError?.contains("repeatedly") == true
		})
		#expect(state.currentSnapshot.usageIsStale)
		try await Task.sleep(for: .milliseconds(30))
		#expect(service.rateLimitReadCount == 4)
	}

	@Test func cancelledUsageFailureCannotInvalidateReconnectedLimits() async throws
	{
		let service = MockCodexService()
		let state = WorkspaceTestFixture(
			server: service,
			storage: makeStorage()
		)
		await state.inputs.connect()
		service.suspendNextRateLimitRead = true
		service.emit(.rateLimitsUpdated)
		#expect(await waitUntil
		{
			service.pendingRateLimitRead != nil
		})
		let obsolete = try #require(service.pendingRateLimitRead)
		service.pendingRateLimitRead = nil
		await state.inputs.connect()
		#expect(!state.currentSnapshot.usageIsStale)
		let timestamp = state.currentSnapshot.usageFetchedAt
		obsolete.resume(throwing: AppServerError.protocolError("Old usage failure"))
		for _ in 0 ..< 10
		{
			await Task.yield()
		}
		#expect(state.currentSnapshot.usageFetchedAt == timestamp)
		#expect(state.currentSnapshot.usageError == nil)
		#expect(!state.currentSnapshot.usageIsStale)
		#expect(service.rateLimitReadCount == 3)
	}

	@Test func usageBecomesVisiblyStaleOnLocalDeadlineAndTimerCancelsOnDisconnect() async throws
	{
		let service = MockCodexService()
		let clock = ControlledUsageClock()
		let state = WorkspaceTestFixture(
			server: service,
			storage: makeStorage(),
			usageRuntime: clock.runtime
		)
		var publishedFreshness: [Bool] = []
		state.onChange =
		{
			publishedFreshness.append($0.usageIsStale)
		}
		await state.inputs.connect()
		#expect(!state.currentSnapshot.usageIsStale)
		let readsAtFreshness = service.rateLimitReadCount
		let publicationsAtFreshness = publishedFreshness.count
		#expect(await waitUntil
		{
			clock.waiterCount == 1
		})
		clock.advance(by: 50)
		#expect(
			await waitUntil
			{
				publishedFreshness.count > publicationsAtFreshness && publishedFreshness
					.last == true
			}
		)
		#expect(service.rateLimitReadCount == readsAtFreshness)

		service.emit(.rateLimitsUpdated)
		#expect(
			await waitUntil
			{
				service.rateLimitReadCount == readsAtFreshness + 1
					&& !state.currentSnapshot.usageIsStale
			}
		)
		service.emitDisconnect("Backend ended.")
		let publicationsAfterDisconnect = publishedFreshness.count
		clock.advance(by: 50)
		for _ in 0 ..< 10
		{
			await Task.yield()
		}
		#expect(publishedFreshness.count == publicationsAfterDisconnect)
	}
}
