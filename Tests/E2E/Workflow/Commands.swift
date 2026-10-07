import Foundation
enum ToolError: Error, CustomStringConvertible
{
	case invalid(String)
	var description: String
	{
		switch self
		{
		case let .invalid(message): return message
		}
	}
}
func output(_ value: String)
{
	FileHandle.standardOutput.write(Data((value + "\n").utf8))
}
func json(
	_ value: Any,
	to url: URL
) throws
{
	try JSONSerialization.data(
		withJSONObject: value,
		options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
	).write(
		to: url,
		options: .atomic
	)
}
@discardableResult
func command(
	_ arguments: [String],
	allowFailure: Bool = false
) throws -> (Int32, String)
{
	let process = Process()
	process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
	process.arguments = arguments
	let pipe = Pipe()
	process.standardOutput = pipe
	// Commands here emit bounded output; inherited stderr keeps errors visible.
	try process.run()
	let data = pipe.fileHandleForReading.readDataToEndOfFile()
	process.waitUntilExit()
	if !allowFailure && process
		.terminationStatus !=
		0
	{
		throw ToolError
			.invalid("Command failed: \(arguments.first ?? "") (\(process.terminationStatus))")
	}
	return (process.terminationStatus, String(
		decoding: data,
		as: UTF8.self
	))
}
