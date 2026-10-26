import Foundation

/// Collects stdout fragments into complete JSONL frames without assuming read boundaries.
final class JSONLineFramer: @unchecked Sendable
{
	private let lock = NSLock()
	private var buffer = Data()
	private var scannedBytes = 0

	func append(_ data: Data) -> [Data]
	{
		lock.lock()
		defer
		{
			lock.unlock()
		}
		buffer.append(data)

		var lines: [Data] = []
		var frameStart = buffer.startIndex
		var searchStart = buffer.index(
			buffer.startIndex,
			offsetBy: scannedBytes
		)
		// Only LF delimits JSONL; Unicode line separators can occur inside JSON strings.
		while let newlineIndex = buffer[searchStart...].firstIndex(of: 0x0A)
		{
			let line = Data(buffer[frameStart ..< newlineIndex])
			searchStart = buffer.index(after: newlineIndex)
			frameStart = searchStart
			if !line.isEmpty
			{
				lines.append(line)
			}
		}
		// Compact once per read and resume after bytes already checked in the partial frame.
		buffer.removeSubrange(buffer.startIndex ..< frameStart)
		scannedBytes = buffer.count

		return lines
	}
}
