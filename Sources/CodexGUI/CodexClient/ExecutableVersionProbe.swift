import Darwin
import Foundation

enum ExecutableVersionProbe
{
	private static let maximumOutputBytes = 4 * 1024
	private static let maximumDrainBytes = 16 * 1024

	static func readVersion(
		from executable: URL,
		timeout: DispatchTimeInterval
	) throws -> String
	{
		let process = Process()
		process.executableURL = executable
		process.arguments = ["--version"]

		let output = Pipe()
		process.standardOutput = output
		process.standardError = FileHandle.nullDevice

		let outputHandle = output.fileHandleForReading
		let descriptor = outputHandle.fileDescriptor
		let flags = fcntl(
			descriptor,
			F_GETFL
		)
		guard flags != -1, fcntl(
			descriptor,
			F_SETFL,
			flags | O_NONBLOCK
		) != -1
		else
		{
			outputHandle.closeFile()
			throw AppServerError.protocolError("Could not configure the Codex version output pipe.")
		}

		let termination = DispatchSemaphore(value: 0)
		process.terminationHandler =
		{
			_ in termination.signal()
		}
		do
		{
			try process.run()
		}
		catch
		{
			process.terminationHandler = nil
			outputHandle.closeFile()
			throw error
		}

		var versionData = Data()
		let deadline = DispatchTime.now() + timeout
		while true
		{
			drainOutput(
				from: descriptor,
				into: &versionData
			)
			if termination.wait(timeout: .now() + .milliseconds(10)) == .success
			{
				break
			}
			if DispatchTime.now() >= deadline
			{
				terminate(
					process,
					waitingFor: termination
				)
				drainOutput(
					from: descriptor,
					into: &versionData
				)
				process.terminationHandler = nil
				outputHandle.closeFile()
				throw AppServerError.requestTimedOut("--version")
			}
		}

		drainOutput(
			from: descriptor,
			into: &versionData
		)
		process.terminationHandler = nil
		outputHandle.closeFile()

		guard process.terminationStatus == 0,
				let version = String(
				data: versionData,
				encoding: .utf8
				)?
				.trimmingCharacters(in: .whitespacesAndNewlines),
				!version.isEmpty
		else
		{
			throw AppServerError.protocolError("Could not read the Codex CLI version.")
		}
		return version
	}

	private static func drainOutput(
		from descriptor: Int32,
		into data: inout Data
	)
	{
		var buffer = [UInt8](
			repeating: 0,
			count: 1024
		)
		var drainedBytes = 0
		var readAttempts = 0
		while drainedBytes < maximumDrainBytes, readAttempts < 32
		{
			readAttempts += 1
			let bytesToRead = min(
				buffer.count,
				maximumDrainBytes - drainedBytes
			)
			let bytesRead = buffer.withUnsafeMutableBytes
			{
				bytes in
				read(
					descriptor,
					bytes.baseAddress,
					bytesToRead
				)
			}
			if bytesRead > 0
			{
				let availableBytes = maximumOutputBytes - data.count
				if availableBytes > 0
				{
					data.append(contentsOf: buffer.prefix(min(
						bytesRead,
						availableBytes
					)))
				}
				drainedBytes += bytesRead
			}
			else if bytesRead == -1, errno == EINTR
			{
				continue
			}
			else
			{
				return
			}
		}
	}

	private static func terminate(
		_ process: Process,
		waitingFor termination: DispatchSemaphore
	)
	{
		let processID = process.processIdentifier
		if process.isRunning
		{
			process.terminate()
		}
		guard termination.wait(timeout: .now() + .milliseconds(250)) == .timedOut
		else
		{
			return
		}
		if process.isRunning
		{
			_ = kill(
				processID,
				SIGKILL
			)
		}
		_ = termination.wait(timeout: .now() + .seconds(1))
	}
}
