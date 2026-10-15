import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AppServerVersionProbeTests
{
	@Test func stalledVersionCheckTimesOutWithoutBlockingMainActor() async throws
	{
		let directory = try await AppServerTestExecutable.temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let executable = try await AppServerTestExecutable.mockExecutable(
			in: directory,
			script: """
			#!/usr/bin/env python3
			import signal
			import time

			signal.signal(signal.SIGTERM, signal.SIG_IGN)
			time.sleep(8)
			"""
		)
		try await assertProbeDoesNotBlockMainActor()
		let (versionError, probeDuration) = try await measureProbe(executable)

		#expect(versionError != nil)
		if case .some(.requestTimedOut("--version")) = versionError
		{
			#expect(true)
		}
		else
		{
			#expect(
				Bool(false),
				"Expected the version probe to time out"
			)
		}
		// Timeout cleanup can wait up to 1.25 seconds before killing the child.
		// This bound still finishes before the 8-second fixture could exit on its own.
		#expect(probeDuration < .seconds(6))
	}

	@Test func continuousVersionOutputCannotStarveProbeDeadline() async throws
	{
		let directory = try await AppServerTestExecutable.temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let executable = try await AppServerTestExecutable.mockExecutable(
			in: directory,
			script: """
			#!/usr/bin/env python3
			import signal
			import sys
			import time

			signal.signal(signal.SIGTERM, signal.SIG_IGN)
			deadline = time.monotonic() + 8
			while time.monotonic() < deadline:
			    sys.stdout.write('x' * 1024)
			    sys.stdout.flush()
			"""
		)
		try await assertProbeDoesNotBlockMainActor()
		let (versionError, probeDuration) = try await measureProbe(executable)

		if case .some(.requestTimedOut("--version")) = versionError
		{
			#expect(true)
		}
		else
		{
			#expect(
				Bool(false),
				"Expected the continuous-output version probe to time out"
			)
		}
		#expect(probeDuration < .seconds(6))
	}
	private func measureProbe(_ executable: URL) async throws -> (AppServerError?, Duration)
	{
		try await BackgroundTestWork.perform
		{
			// Measure the real probe itself, excluding unrelated main-actor scheduling.
			let clock = ContinuousClock()
			let startedAt = clock.now
			var failure: AppServerError?
			do
			{
				_ = try ExecutableVersionProbe.readVersion(
					from: executable,
					timeout: .seconds(3)
				)
			}
			catch let error as AppServerError
			{
				failure = error
			}
			catch
			{
				throw error
			}
			return (failure, startedAt.duration(to: clock.now))
		}
	}

	private func assertProbeDoesNotBlockMainActor() async throws
	{
		let gate = SuspendedVersionProbe()
		let server = AppServer(
			executableOverride: URL(fileURLWithPath: "/fixture/version-probe"),
			readExecutableVersion:
			{
				_, _ in
				try gate.read()
			}
		)
		var completed = false
		let operation = Task
		{
			defer
			{
				completed = true
			}
			return try await server.executableVersion()
		}
		defer
		{
			operation.cancel()
			gate.release()
		}
		var arrivals = gate.entered.makeAsyncIterator()
		try #require(
			await arrivals.next() != nil,
			"The version probe did not start"
		)
		// The main actor reaches this checkpoint while the synchronous probe is still held.
		#expect(!completed)
		gate.release()
		let version = try? await withTaskCancellationHandler
		{
			try await operation.value
		}
		onCancel:
		{
			operation.cancel()
			gate.release()
		}
		#expect(version == "codex-cli 0.153.2")
	}

}

private final class SuspendedVersionProbe: @unchecked Sendable
{
	let entered: AsyncStream<Void>
	private let arrival: AsyncStream<Void>.Continuation
	private let resume = DispatchSemaphore(value: 0)

	init()
	{
		let stream = AsyncStream<Void>.makeStream()
		entered = stream.stream
		arrival = stream.continuation
	}

	func read() throws -> String
	{
		arrival.yield(())
		arrival.finish()
		// A synchronous call on the main thread must fail before blocking the test actor.
		guard !Thread.isMainThread
		else
		{
			Issue.record("Version probing ran synchronously on the main thread")
			throw AppServerError.protocolError("Version probe blocked the main actor")
		}
		guard resume.wait(timeout: .now() + .seconds(10)) == .success
		else
		{
			throw AppServerError.requestTimedOut("test version probe gate")
		}
		return "codex-cli 0.153.2"
	}

	func release()
	{
		arrival.finish()
		resume.signal()
	}
}
