import Foundation
import Darwin
func processes() throws -> [(Int32, String)]
{
	try command(["ps", "-axo", "pid=,command="]).1.split(separator: "\n").compactMap
	{
		line in
		let fields = line.trimmingCharacters(in: .whitespaces).split(
			maxSplits: 1,
			whereSeparator:
			{
				$0 == " " || $0 == "\t"
			}
		)
		guard fields.count == 2, let pid = Int32(fields[0])
		else
		{
			return nil
		}
		return (pid, String(fields[1]))
	}
}
func cleanup(_ batch: URL) throws
{
	let prefix = batch.path + "/"
	for (pid, text) in try processes() where pid != getpid()
	{
		let owned = text
			.hasPrefix(prefix) ||
			(text.contains(prefix + "run-") && text.hasSuffix("/qa-backend app-server --stdio"))
		if owned
		{
			kill(
				pid,
				SIGTERM
			)
		}
	}
}
var interrupted: sig_atomic_t = 0
func handleSignal(_ value: Int32)
{
	interrupted = value
}

func acquireWorkflowLock(_ url: URL) throws -> Int32
{
	let descriptor = open(
		url.path,
		O_CREAT | O_RDWR | O_CLOEXEC,
		0o600
	)
	guard descriptor >= 0
	else
	{
		throw ToolError.invalid("Cannot open workflow lock")
	}
	guard flock(
		descriptor,
		LOCK_EX | LOCK_NB
	) == 0
	else
	{
		close(descriptor)
		throw ToolError.invalid("Another UI workflow runner owns the desktop/build lock")
	}
	return descriptor
}
