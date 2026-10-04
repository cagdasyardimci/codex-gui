import Foundation

@MainActor
final class RuntimeSignal
{
	private var fired = false
	private var waiters: [CheckedContinuation<Void, Never>] = []
	func wait() async
	{
		guard !fired
		else
		{
			return
		}
		await withCheckedContinuation
		{
			waiters.append($0)
		}
	}
	func signal()
	{
		fired = true
		let pending = waiters
		waiters.removeAll()
		for continuation in pending
		{
			continuation.resume()
		}
	}
}
