import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct RuntimeControlledWaitCancellationTests
{
	@Test(
		.timeLimit(.minutes(1)),
		arguments: [false, true]
	)
	func publicationCancellationRemovesOnlyItsOwnWaiter(afterRegistration: Bool) async throws
	{
		let gate = PublicationGate()
		let active = Task
		{
			await gate.wait()
		}
		defer
		{
			active.cancel()
		}
		try #require(await awaitWaiterCount(
			1,
			currentCount:
			{
				gate.waiterCount
			},
			setOnChange:
			{
				gate.onWaitersChanged = $0
			}
		))
		let canceled = Task
		{
			await gate.wait()
		}
		defer
		{
			canceled.cancel()
		}
		if afterRegistration
		{
			try #require(await awaitWaiterCount(
				2,
				currentCount:
				{
					gate.waiterCount
				},
				setOnChange:
				{
					gate.onWaitersChanged = $0
				}
			))
		}
		// Without an await, the actor-owned task cannot start before cancellation.
		canceled.cancel()
		await canceled.value
		#expect(gate.waiterCount == 1)
		#expect(gate.isWaiting)
		gate.release()
		gate.release()
		await active.value
		#expect(gate.waiterCount == 0)
		#expect(!gate.isWaiting)

		let replacement = Task
		{
			await gate.wait()
		}
		defer
		{
			replacement.cancel()
		}
		try #require(await awaitWaiterCount(
			1,
			currentCount:
			{
				gate.waiterCount
			},
			setOnChange:
			{
				gate.onWaitersChanged = $0
			}
		))
		canceled.cancel()
		#expect(gate.waiterCount == 1)
		gate.release()
		await replacement.value
		#expect(!gate.isWaiting)
	}

	@Test(
		.timeLimit(.minutes(1)),
		arguments: [false, true]
	)
	func usageCancellationRemovesOnlyItsOwnWaiter(afterRegistration: Bool) async throws
	{
		let clock = ControlledUsageClock()
		let runtime = clock.runtime
		let initialTime = runtime.now()
		let active = Task
		{
			try await runtime.waitUntil(initialTime.addingTimeInterval(50))
		}
		defer
		{
			active.cancel()
		}
		try #require(await awaitWaiterCount(
			1,
			currentCount:
			{
				clock.waiterCount
			},
			setOnChange:
			{
				clock.onWaitersChanged = $0
			}
		))
		let canceled = Task
		{
			try await runtime.waitUntil(initialTime.addingTimeInterval(25))
		}
		defer
		{
			canceled.cancel()
		}
		if afterRegistration
		{
			try #require(await awaitWaiterCount(
				2,
				currentCount:
				{
					clock.waiterCount
				},
				setOnChange:
				{
					clock.onWaitersChanged = $0
				}
			))
		}
		canceled.cancel()
		let result = await canceled.result
		if case .failure(let error) = result
		{
			#expect(error is CancellationError)
		}
		else
		{
			Issue.record("A canceled usage wait must throw CancellationError.")
		}
		#expect(clock.waiterCount == 1)
		clock.advance(by: 25)
		#expect(clock.waiterCount == 1)
		clock.advance(by: 25)
		try await active.value
		#expect(clock.waiterCount == 0)
		canceled.cancel()
		clock.advance(by: 50)
		#expect(clock.waiterCount == 0)
	}

	@Test(
		.timeLimit(.minutes(1)),
		arguments: [false, true]
	)
	func cancellationRacingReleaseResumesEachWaiterOnce(cancelBeforeRelease: Bool) async throws
	{
		let gate = PublicationGate()
		let clock = ControlledUsageClock()
		let runtime = clock.runtime
		let deadline = runtime.now().addingTimeInterval(50)
		let publication = Task
		{
			await gate.wait()
		}
		let usage = Task
		{
			try await runtime.waitUntil(deadline)
		}
		defer
		{
			publication.cancel()
			usage.cancel()
		}
		try #require(await awaitWaiterCount(
			1,
			currentCount:
			{
				gate.waiterCount
			},
			setOnChange:
			{
				gate.onWaitersChanged = $0
			}
		))
		try #require(await awaitWaiterCount(
			1,
			currentCount:
			{
				clock.waiterCount
			},
			setOnChange:
			{
				clock.onWaitersChanged = $0
			}
		))
		if cancelBeforeRelease
		{
			publication.cancel()
			usage.cancel()
		}
		gate.release()
		clock.advance(by: 50)
		if !cancelBeforeRelease
		{
			// Both removals happen before resumption; cancellation must not resume them again.
			publication.cancel()
			usage.cancel()
		}
		await publication.value
		let result = await usage.result
		if case .failure(let error) = result
		{
			#expect(error is CancellationError)
		}
		else
		{
			Issue.record("A usage wait canceled before resumption must throw CancellationError.")
		}
		#expect(!gate.isWaiting)
		#expect(clock.waiterCount == 0)
		gate.release()
		clock.advance(by: 50)
		#expect(!gate.isWaiting)
		#expect(clock.waiterCount == 0)
	}

	private func awaitWaiterCount(
		_ count: Int,
		currentCount: @escaping () -> Int,
		setOnChange: ((() -> Void)?) -> Void
	) async -> Bool
	{
		guard !Task.isCancelled
		else
		{
			return false
		}
		if currentCount() == count
		{
			return true
		}
		let checkpoint = AsyncStream<Void>.makeStream()
		defer
		{
			setOnChange(nil)
			checkpoint.continuation.finish()
		}
		setOnChange
		{
			guard currentCount() == count
			else
			{
				return
			}
			checkpoint.continuation.yield(())
			checkpoint.continuation.finish()
		}
		for await _ in checkpoint.stream
		{
			return !Task.isCancelled && currentCount() == count
		}
		return false
	}
}
