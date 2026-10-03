import Foundation

struct GitCommandOutput
{
	let bytes: Data
	let terminationStatus: Int32
}

enum GitCommandRunnerError: Error
{
	case oversized
}

/// Runs a fully specified Git argument list. Callers own exit-status and error policy.
enum GitCommandRunner
{
	static func run(
		arguments: [String],
		maximumBytes: Int
	) throws -> GitCommandOutput
	{
		try Task.checkCancellation()
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
		process.arguments = arguments
		process.environment = sanitizedEnvironment(ProcessInfo.processInfo.environment)

		let output = Pipe()
		process.standardOutput = output
		process.standardError = FileHandle.nullDevice
		process.standardInput = FileHandle.nullDevice
		defer
		{
			output.fileHandleForReading.closeFile()
			output.fileHandleForWriting.closeFile()
		}

		let control = GitSubprocessCancellation.current
		if let control
		{
			try control.launch(process)
		}
		else
		{
			try process.run()
		}
		defer
		{
			control?.finish(process)
		}

		let capturedOutput = readBoundedOutput(
			from: output.fileHandleForReading,
			process: process,
			maximumBytes: maximumBytes
		)
		process.waitUntilExit()
		try Task.checkCancellation()
		if capturedOutput.exceededLimit
		{
			throw GitCommandRunnerError.oversized
		}
		return GitCommandOutput(
			bytes: capturedOutput.bytes,
			terminationStatus: process.terminationStatus
		)
	}

	private static func readBoundedOutput(
		from handle: FileHandle,
		process: Process,
		maximumBytes: Int
	) -> (bytes: Data, exceededLimit: Bool)
	{
		let readChunkSize = 65_536
		var bytes = Data()
		var exceededOutputLimit = false
		while true
		{
			let chunk = handle.readData(ofLength: readChunkSize)
			if chunk.isEmpty
			{
				break
			}
			if bytes.count + chunk.count > maximumBytes
			{
				if !exceededOutputLimit
				{
					exceededOutputLimit = true
					if process.isRunning
					{
						process.terminate()
					}
				}
			}
			else if !exceededOutputLimit
			{
				bytes.append(chunk)
			}
		}
		return (bytes, exceededOutputLimit)
	}

	private static func sanitizedEnvironment(_ inherited: [String: String]) -> [String: String]
	{
		var environment = inherited
		for key in environment.keys
			where key.hasPrefix("GIT_")
		{
			environment.removeValue(forKey: key)
		}
		environment["GIT_OPTIONAL_LOCKS"] = "0"
		environment["GIT_TERMINAL_PROMPT"] = "0"
		environment["GIT_CONFIG_NOSYSTEM"] = "1"
		environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
		return environment
	}
}
