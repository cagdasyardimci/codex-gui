import Foundation
import Testing

@testable import CodexGUI

extension ApplicationStateTests
{
	@Test(.timeLimit(.minutes(1))) func sparseUsageUpdatesCoalesceDuringAnActiveRead() async throws
	{
		let service = MockCodexService()
		service.rateLimitSnapshotsByReadNumber[3] = usageSnapshot(
			usedPercent: 70,
			windowDurationMins: 10080,
			resetsAt: 3000
		)
		let defaultsFixture = try IsolatedUserDefaultsFixture(prefix: "CodexGUIStateTests")
		defer
		{
			defaultsFixture.cleanup()
		}
		let state = WorkspaceTestFixture(
			server: service,
			storage: LocalStorage(defaults: defaultsFixture.defaults)
		)
		defer
		{
			state.shutdown()
			service.pendingRateLimitRead?.resume(throwing: CancellationError())
			service.pendingRateLimitRead = nil
		}
		await state.inputs.connect()
		#expect(service.rateLimitReadCount == 1)
		#expect(state.currentSnapshot.usage?.rateLimits.primary?.usedPercent == 20)
		service.suspendNextRateLimitRead = true
		service.emit(.rateLimitsUpdated)
		let refresh = try #require(state.store.model.usage.pendingRefresh)
		let operation = try #require(state.store.operation(for: refresh.context))
		#expect(await service.awaitReadiness(matching:
			{
				service.pendingRateLimitRead != nil
			}))
		service.emit(.rateLimitsUpdated)
		service.emit(.rateLimitsUpdated)
		service.finishPendingRateLimitRead(
			with: usageSnapshot(
				usedPercent: 40,
				windowDurationMins: 300,
				resetsAt: 2000
			)
		)
		try Task.checkCancellation()
		#expect(await operation.wait() == .finished)
		#expect(service.rateLimitReadCount == 3)
		let finalWindow = try #require(state.currentSnapshot.usage?.rateLimits.primary)
		#expect(finalWindow.usedPercent == 70)
		#expect(finalWindow.windowDurationMins == 10080)
		#expect(finalWindow.resetsAt == Date(timeIntervalSince1970: 3000))
		// Finite completion includes all coalesced follow-up reads; no delay can prove this.
		#expect(service.rateLimitReadCount == 3)
	}

	@Test(.timeLimit(
		.minutes(1)
	)) func usageUpdateDuringSecondReadGetsOneMoreBoundedRead() async throws
	{
		let service = MockCodexService()
		service.rateLimitSnapshotsByReadNumber[4] = usageSnapshot(
			usedPercent: 80,
			windowDurationMins: 10080,
			resetsAt: 4000
		)
		let defaultsFixture = try IsolatedUserDefaultsFixture(prefix: "CodexGUIStateTests")
		defer
		{
			defaultsFixture.cleanup()
		}
		let state = WorkspaceTestFixture(
			server: service,
			storage: LocalStorage(defaults: defaultsFixture.defaults)
		)
		defer
		{
			state.shutdown()
			service.pendingRateLimitRead?.resume(throwing: CancellationError())
			service.pendingRateLimitRead = nil
		}
		await state.inputs.connect()
		service.suspendRateLimitReadNumbers = [2, 3]
		service.emit(.rateLimitsUpdated)
		let refresh = try #require(state.store.model.usage.pendingRefresh)
		let operation = try #require(state.store.operation(for: refresh.context))
		#expect(
			await service.awaitReadiness(matching:
				{
					service.rateLimitReadCount == 2
						&& service.pendingRateLimitRead != nil
				})
		)
		service.emit(.rateLimitsUpdated)
		service.finishPendingRateLimitRead(with: usageSnapshot(
			usedPercent: 40,
			windowDurationMins: 300,
			resetsAt: 2000
		))
		#expect(
			await service.awaitReadiness(matching:
				{
					service.rateLimitReadCount == 3
						&& service.pendingRateLimitRead != nil
				})
		)
		#expect(state.currentSnapshot.usage?.rateLimits.primary?.usedPercent == 40)
		service.emit(.rateLimitsUpdated)
		service.finishPendingRateLimitRead(with: usageSnapshot(
			usedPercent: 60,
			windowDurationMins: 1440,
			resetsAt: 3000
		))
		try Task.checkCancellation()
		#expect(await operation.wait() == .finished)
		#expect(service.rateLimitReadCount == 4)
		let finalWindow = try #require(state.currentSnapshot.usage?.rateLimits.primary)
		#expect(finalWindow.usedPercent == 80)
		#expect(finalWindow.windowDurationMins == 10080)
		#expect(finalWindow.resetsAt == Date(timeIntervalSince1970: 4000))
		#expect(state.currentSnapshot.usageError == nil)
		#expect(!state.currentSnapshot.usageIsStale)
	}

	@Test(
		.timeLimit(.minutes(1))
	) func repeatedUsageInvalidationsStopAtThreeReadsAndShowStaleWarning() async throws
	{
		let service = MockCodexService()
		let defaultsFixture = try IsolatedUserDefaultsFixture(prefix: "CodexGUIStateTests")
		defer
		{
			defaultsFixture.cleanup()
		}
		let state = WorkspaceTestFixture(
			server: service,
			storage: LocalStorage(defaults: defaultsFixture.defaults)
		)
		defer
		{
			state.shutdown()
			service.pendingRateLimitRead?.resume(throwing: CancellationError())
			service.pendingRateLimitRead = nil
		}
		await state.inputs.connect()
		service.suspendRateLimitReadNumbers = [2, 3, 4]
		service.emit(.rateLimitsUpdated)
		let refresh = try #require(state.store.model.usage.pendingRefresh)
		let operation = try #require(state.store.operation(for: refresh.context))
		let refreshSnapshots = [
			usageSnapshot(
				usedPercent: 40,
				windowDurationMins: 300,
				resetsAt: 2000
			),
			usageSnapshot(
				usedPercent: 60,
				windowDurationMins: 1440,
				resetsAt: 3000
			),
			usageSnapshot(
				usedPercent: 80,
				windowDurationMins: 10080,
				resetsAt: 4000
			),
		]
		for (readCount, snapshot) in zip(
			2 ... 4,
			refreshSnapshots
		)
		{
			#expect(
				await service.awaitReadiness(matching:
					{
						service.rateLimitReadCount == readCount
							&& service.pendingRateLimitRead != nil
					})
			)
			service.emit(.rateLimitsUpdated)
			service.finishPendingRateLimitRead(with: snapshot)
		}
		try Task.checkCancellation()
		#expect(await operation.wait() == .finished)
		#expect(state.currentSnapshot.usageError?.contains("repeatedly") == true)
		#expect(state.currentSnapshot.usageIsStale)
		let finalWindow = try #require(state.currentSnapshot.usage?.rateLimits.primary)
		#expect(finalWindow.usedPercent == 80)
		#expect(finalWindow.windowDurationMins == 10080)
		#expect(finalWindow.resetsAt == Date(timeIntervalSince1970: 4000))
		// The completed group cannot schedule another read after exhausting its attempt budget.
		#expect(service.rateLimitReadCount == 4)
	}

	@Test(.timeLimit(
		.minutes(1)
	)) func cancelledUsageFailureCannotInvalidateReconnectedLimits() async throws
	{
		let service = MockCodexService()
		let defaultsFixture = try IsolatedUserDefaultsFixture(prefix: "CodexGUIStateTests")
		defer
		{
			defaultsFixture.cleanup()
		}
		let state = WorkspaceTestFixture(
			server: service,
			storage: LocalStorage(defaults: defaultsFixture.defaults)
		)
		defer
		{
			state.shutdown()
			service.pendingRateLimitRead?.resume(throwing: CancellationError())
			service.pendingRateLimitRead = nil
		}
		await state.inputs.connect()
		service.suspendNextRateLimitRead = true
		service.emit(.rateLimitsUpdated)
		#expect(await service.awaitReadiness(matching:
			{
				service.pendingRateLimitRead != nil
			}))
		let refresh = try #require(state.store.model.usage.pendingRefresh)
		let operation = try #require(state.store.operation(for: refresh.context))
		let executions = state.store.executionTasks(for: refresh.context)
		try #require(!executions.isEmpty)
		let obsolete = try #require(service.pendingRateLimitRead)
		service.pendingRateLimitRead = nil
		await state.inputs.connect()
		#expect(!state.currentSnapshot.usageIsStale)
		let timestamp = state.currentSnapshot.usageFetchedAt
		obsolete.resume(throwing: AppServerError.protocolError("Old usage failure"))
		// Cancellation completes the handle early; await the captured execution's return too.
		#expect(await operation.wait() == .cancelled)
		for execution in executions
		{
			await execution.value
		}
		#expect(state.currentSnapshot.usageFetchedAt == timestamp)
		#expect(state.currentSnapshot.usageError == nil)
		#expect(!state.currentSnapshot.usageIsStale)
		#expect(service.rateLimitReadCount == 3)
	}

	@Test(
		.timeLimit(.minutes(1))
	) func usageBecomesVisiblyStaleOnLocalDeadlineAndTimerCancelsOnDisconnect() async throws
	{
		let service = MockCodexService()
		let clock = ControlledUsageClock()
		let defaultsFixture = try IsolatedUserDefaultsFixture(prefix: "CodexGUIStateTests")
		defer
		{
			defaultsFixture.cleanup()
		}
		let state = WorkspaceTestFixture(
			server: service,
			storage: LocalStorage(defaults: defaultsFixture.defaults),
			usageRuntime: clock.runtime
		)
		var publishedFreshness: [Bool] = []
		state.onChange =
		{
			publishedFreshness.append($0.usageIsStale)
		}
		defer
		{
			state.shutdown()
			service.pendingRateLimitRead?.resume(throwing: CancellationError())
			service.pendingRateLimitRead = nil
		}
		await state.inputs.connect()
		#expect(!state.currentSnapshot.usageIsStale)
		let readsAtFreshness = service.rateLimitReadCount
		let publicationsAtFreshness = publishedFreshness.count
		#expect(await awaitUsageClock(clock)
		{
			clock.waiterCount == 1
		})
		clock.advance(by: 50)
		#expect(
			await awaitUsagePublication(
				state,
				matching:
				{
					publishedFreshness.count > publicationsAtFreshness && publishedFreshness
						.last == true
				}
			)
		)
		#expect(service.rateLimitReadCount == readsAtFreshness)

		service.emit(.rateLimitsUpdated)
		#expect(
			await awaitUsagePublication(
				state,
				matching:
				{
					service.rateLimitReadCount == readsAtFreshness + 1
						&& !state.currentSnapshot.usageIsStale
				}
			)
		)
		#expect(await awaitUsageClock(clock)
		{
			clock.waiterCount == 1
		})
		let deadline = try #require(state.store.model.usage.pendingDeadline)
		let executions = state.store.executionTasks(for: deadline.read.context)
		try #require(!executions.isEmpty)
		service.emitDisconnect("Backend ended.")
		let publicationsAfterDisconnect = publishedFreshness.count
		clock.advance(by: 50)
		// The canceled deadline must leave the runtime before asserting no late publication.
		for execution in executions
		{
			await execution.value
		}
		#expect(clock.waiterCount == 0)
		#expect(publishedFreshness.count == publicationsAfterDisconnect)
	}

	private func usageSnapshot(
		usedPercent: Double,
		windowDurationMins: Int,
		resetsAt: TimeInterval
	) -> AccountRateLimitsSnapshot
	{
		AccountRateLimitsSnapshot(json: [
			"rateLimits": ["primary": [
				"usedPercent": usedPercent,
				"windowDurationMins": windowDurationMins,
				"resetsAt": resetsAt,
			]],
		])!
	}

	private func awaitUsageClock(
		_ clock: ControlledUsageClock,
		matching predicate: @escaping @MainActor () -> Bool
	) async -> Bool
	{
		let previous = clock.onWaitersChanged
		defer
		{
			clock.onWaitersChanged = previous
		}
		let stream = AsyncStream<Void>
		{
			continuation in
			let check: @MainActor () -> Void =
			{
				guard predicate()
				else
				{
					return
				}
				continuation.yield(())
				continuation.finish()
			}
			clock.onWaitersChanged =
			{
				previous?()
				check()
			}
			check()
		}
		for await _ in stream
		{
			break
		}
		return predicate()
	}

	private func awaitUsagePublication(
		_ state: WorkspaceTestFixture,
		matching predicate: @escaping @MainActor () -> Bool
	) async -> Bool
	{
		let previous = state.onChange
		defer
		{
			state.onChange = previous
		}
		let stream = AsyncStream<Void>
		{
			continuation in
			let check: @MainActor () -> Void =
			{
				guard predicate()
				else
				{
					return
				}
				continuation.yield(())
				continuation.finish()
			}
			state.onChange =
			{
				snapshot in
				previous?(snapshot)
				check()
			}
			check()
		}
		for await _ in stream
		{
			break
		}
		return predicate()
	}
}
