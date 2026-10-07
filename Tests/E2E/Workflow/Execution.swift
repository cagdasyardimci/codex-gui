import Foundation
import Darwin
func boundedCommand(
	_ arguments: [String],
	seconds: Double,
	log: URL,
	environment: [String: String]? = nil,
	stdout: URL? = nil
) throws -> Int32
{
	let process = Process()
	process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
	process.arguments = arguments
	if let environment
	{
		process.environment = environment
	}
	_ = FileManager.default.createFile(
		atPath: log.path,
		contents: nil
	)
	let file = try FileHandle(forWritingTo: log)
	defer
	{
		try? file.close()
	}
	var outputFile: FileHandle?
	if let stdout
	{
		_ = FileManager.default.createFile(
			atPath: stdout.path,
			contents: nil
		)
		outputFile = try FileHandle(forWritingTo: stdout)
	}
	defer
	{
		try? outputFile?.close()
	}
	process.standardOutput = outputFile ?? file; process.standardError = file
	try process.run()
	// Foundation spawns a separate process group on Darwin; verify it before signalling a group.
	let group = getpgid(process.processIdentifier)
	let ownedGroup = group == process.processIdentifier
	let deadline = Date().addingTimeInterval(seconds)
	var forced: Int32?
	while process.isRunning
	{
		if interrupted != 0 || Date() > deadline
		{
			forced = interrupted != 0 ? 130 : 124
			kill(
				ownedGroup ? -group : process.processIdentifier,
				SIGTERM
			)
			let grace = Date().addingTimeInterval(5)
			while process.isRunning && Date() < grace
			{
				Thread.sleep(forTimeInterval: 0.1)
			}
			if process.isRunning
			{
				kill(
					ownedGroup ? -group : process.processIdentifier,
					SIGKILL
				)
			}
			break
		}

		Thread.sleep(forTimeInterval: 0.1)
	}
	process.waitUntilExit()
	if let forced
	{
		try file.seekToEnd()
		try file
			.write(contentsOf: Data((forced == 130 ? "\nWorkflow interrupted.\n" :
					"\nWorkflow exceeded its runner deadline.\n").utf8))
	}
	return forced ?? process.terminationStatus
}
