import Foundation

/// Collects stdout fragments into complete JSONL frames without assuming read boundaries.
final class JSONLineFramer: @unchecked Sendable
{
	private let lock = NSLock()
	private var buffer = Data()

	func append(_ data: Data) -> [Data]
	{
		lock.lock()
		defer
		{
			lock.unlock()
		}
		buffer.append(data)

		var lines: [Data] = []
		// Only LF delimits JSONL; Unicode line separators can occur inside JSON strings.
		while let newlineIndex = buffer.firstIndex(of: 0x0A)
		{
			let line = Data(buffer[..<newlineIndex])
			buffer.removeSubrange(...newlineIndex)
			if !line.isEmpty
			{
				lines.append(line)
			}
		}

		return lines
	}
}
