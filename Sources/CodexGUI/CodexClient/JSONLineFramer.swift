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
		var lines: [Data] = []
		data.withUnsafeBytes
		{
			bytes in
			guard let base = bytes.baseAddress
			else
			{
				return
			}
			var frameStart = 0
			// Only LF delimits JSONL; Unicode separators can occur inside JSON strings.
			while frameStart < bytes.count,
					let newline = memchr(
					base.advanced(by: frameStart),
					0x0A,
					bytes.count - frameStart
					)
			{
				let newlineOffset = base.distance(to: UnsafeRawPointer(newline))
				let fragment =
					data[(data.startIndex + frameStart) ..< (data.startIndex + newlineOffset)]
				if !buffer.isEmpty
				{
					buffer.append(fragment)
					lines.append(buffer)
					buffer = Data()
				}
				else if !fragment.isEmpty
				{
					lines.append(Data(fragment))
				}
				frameStart = newlineOffset + 1
			}
			// Retain only an unfinished frame, independently of the incoming read's storage.
			if frameStart < bytes.count
			{
				let tailStart = data.startIndex + frameStart
				if buffer.isEmpty
				{
					buffer = data.subdata(in: tailStart ..< data.endIndex)
				}
				else
				{
					buffer.append(data[tailStart...])
				}
			}
		}

		return lines
	}
}
