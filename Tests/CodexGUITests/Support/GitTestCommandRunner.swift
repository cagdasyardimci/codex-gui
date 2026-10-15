import Foundation

/// Runs fixture Git commands without sharing the production command runner's implementation.
enum GitTestCommandRunner
{
	struct Result: Sendable
	{
		let output: Data
		let terminationStatus: Int32
	}

	/// Optionally merges stderr into output so fixture failures retain Git's diagnostics.
	static func run(
		in directory: URL,
		arguments: [String],
		input: Data? = nil,
		captureStandardError: Bool = false,
		environment inheritedEnvironment: [String: String] = ProcessInfo.processInfo.environment
	) throws -> Result
	{
		let timing = TestTiming.begin(
			"git.command",
			detail: arguments.joined(separator: " ")
		)
		defer
		{
			timing.end()
		}
		return try execute(
			in: directory,
			arguments: arguments,
			input: input,
			captureStandardError: captureStandardError,
			environment: inheritedEnvironment
		)
	}

	/// Await fixture Git commands from actor-isolated tests without blocking their actor.
	static func runAsync(
		in directory: URL,
		arguments: [String],
		input: Data? = nil,
		captureStandardError: Bool = false,
		environment inheritedEnvironment: [String: String] = ProcessInfo.processInfo.environment
	) async throws -> Result
	{
		let timing = TestTiming.begin(
			"git.command",
			detail: arguments.joined(separator: " ")
		)
		defer
		{
			timing.end()
		}
		return try await BackgroundTestWork.perform
		{
			timing.mark("execution.begin")
			defer
			{
				timing.mark("execution.end")
			}
			return try execute(
				in: directory,
				arguments: arguments,
				input: input,
				captureStandardError: captureStandardError,
				environment: inheritedEnvironment
			)
		}
	}

	private static func execute(
		in directory: URL,
		arguments: [String],
		input: Data?,
		captureStandardError: Bool,
		environment inheritedEnvironment: [String: String]
	) throws -> Result
	{
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
		process.arguments = [
			"--no-optional-locks",
			"-c",
			"core.hooksPath=/dev/null",
			"-c",
			"commit.gpgsign=false",
			"-c",
			"core.fsmonitor=false",
			"-C",
			directory.path
		] + arguments
		process.environment = sanitizedEnvironment(inheritedEnvironment)

		let output = Pipe()
		defer
		{
			try? output.fileHandleForReading.close()
			try? output.fileHandleForWriting.close()
		}
		let capturesOutput = input == nil || captureStandardError
		if captureStandardError
		{
			process.standardError = output
		}
		else
		{
			process.standardError = FileHandle.nullDevice
		}
		if capturesOutput
		{
			process.standardOutput = output
		}
		else
		{
			process.standardOutput = FileHandle.nullDevice
		}
		let inputPipe = input == nil ? nil : Pipe()
		defer
		{
			try? inputPipe?.fileHandleForReading.close()
			try? inputPipe?.fileHandleForWriting.close()
		}
		if let inputPipe
		{
			process.standardInput = inputPipe
		}
		else
		{
			process.standardInput = FileHandle.nullDevice
		}

		try process.run()
		if let inputPipe, let input
		{
			inputPipe.fileHandleForWriting.write(input)
			try inputPipe.fileHandleForWriting.close()
		}
		let bytes = capturesOutput ? output.fileHandleForReading.readDataToEndOfFile() : Data()
		process.waitUntilExit()
		return Result(
			output: bytes,
			terminationStatus: process.terminationStatus
		)
	}

	private static func sanitizedEnvironment(
		_ inheritedEnvironment: [String: String]
	) -> [String: String]
	{
		var environment = inheritedEnvironment
		for key in environment.keys where key.hasPrefix("GIT_")
		{
			environment.removeValue(forKey: key)
		}
		environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
		environment["GIT_CONFIG_NOSYSTEM"] = "1"
		environment["GIT_TERMINAL_PROMPT"] = "0"
		return environment
	}
}
