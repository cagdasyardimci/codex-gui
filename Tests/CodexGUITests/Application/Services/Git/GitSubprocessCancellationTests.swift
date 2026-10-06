import Foundation
import Testing

@testable import CodexGUI

struct GitSubprocessCancellationTests
{
	@Test func cancellingComparisonStopsDetachedProcess() async throws
	{
		let started = DispatchSemaphore(value: 0)
		let work = Task
		{
			await GitSubprocessCancellation.detached
			{
				let process = Process()
				process.executableURL = URL(fileURLWithPath: "/bin/sleep")
				process.arguments = ["5"]
				guard let control = GitSubprocessCancellation.current
				else
				{
					return false
				}
				do
				{
					try control.launch(process)
					started.signal()
					process.waitUntilExit()
					control.finish(process)
					return Task.isCancelled && process.terminationStatus != 0
				}
				catch
				{
					return false
				}
			}
		}
		let didStart = await Task.detached
		{
			Self.waitForSignal(started)
		}.value
		#expect(didStart)
		let cancelledAt = Date()
		work.cancel()
		#expect(await work.value)
		#expect(Date().timeIntervalSince(cancelledAt) < 2)
	}

	private static func waitForSignal(_ semaphore: DispatchSemaphore) -> Bool
	{
		semaphore.wait(timeout: .now() + 2) == .success
	}
}
