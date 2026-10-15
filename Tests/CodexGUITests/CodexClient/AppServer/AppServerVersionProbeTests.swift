import Foundation
import Testing

@testable import CodexGUI

@MainActor
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
		let server = AppServer(
			executableOverride: executable,
			versionCheckTimeout: .seconds(3)
		)
		let clock = ContinuousClock()
		let startedAt = clock.now
		let versionTask = Task
		{
			try await server.executableVersion()
		}
		let mainActorProgressTask = Task
		{
			@MainActor in
			try? await Task.sleep(for: .milliseconds(100))
			return clock.now
		}
		let mainActorProgressTime = await mainActorProgressTask.value
		// A synchronous probe would hold the main actor through the 3-second deadline.
		// Leave room for scheduling delays when other test suites run in parallel.
		#expect(startedAt.duration(to: mainActorProgressTime) < .seconds(2.5))

		var versionError: AppServerError?
		do
		{
			_ = try await versionTask.value
		}
		catch let error as AppServerError
		{
			versionError = error
		}
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
		#expect(startedAt.duration(to: clock.now) < .seconds(6))
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
		let server = AppServer(
			executableOverride: executable,
			versionCheckTimeout: .seconds(3)
		)
		let clock = ContinuousClock()
		let startedAt = clock.now
		let versionTask = Task
		{
			try await server.executableVersion()
		}
		let mainActorProgressTask = Task
		{
			@MainActor in
			try? await Task.sleep(for: .milliseconds(100))
			return clock.now
		}
		let mainActorProgressTime = await mainActorProgressTask.value
		#expect(startedAt.duration(to: mainActorProgressTime) < .seconds(2.5))

		var versionError: AppServerError?
		do
		{
			_ = try await versionTask.value
		}
		catch let error as AppServerError
		{
			versionError = error
		}
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
		#expect(startedAt.duration(to: clock.now) < .seconds(6))
	}
}
