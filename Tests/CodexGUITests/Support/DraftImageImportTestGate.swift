import Foundation

@testable import CodexGUI

/// Holds preparation in a background worker while a test changes the captured UI owner.
final class DraftImageImportTestGate: @unchecked Sendable
{
	private let condition = NSCondition()
	private var startedCount = 0
	private var released = false

	var preparationCount: Int
	{
		condition.lock()
		defer
		{
			condition.unlock()
		}
		return startedCount
	}

	func prepare(_ source: DraftImageSource) throws -> Data
	{
		condition.lock()
		startedCount += 1
		condition.broadcast()
		let deadline = Date().addingTimeInterval(10)
		while !released, condition.wait(until: deadline)
		{
		}
		let wasReleased = released
		condition.unlock()
		guard wasReleased
		else
		{
			throw CancellationError()
		}
		return try source.pngData()
	}

	func waitUntilStarted() async -> Bool
	{
		await Task.detached
		{
			self.waitForPreparation()
		}.value
	}

	private func waitForPreparation() -> Bool
	{
		condition.lock()
		defer
		{
			condition.unlock()
		}
		let deadline = Date().addingTimeInterval(10)
		while startedCount == 0, condition.wait(until: deadline)
		{
		}
		return startedCount > 0
	}

	func release()
	{
		condition.lock()
		released = true
		condition.broadcast()
		condition.unlock()
	}
}
