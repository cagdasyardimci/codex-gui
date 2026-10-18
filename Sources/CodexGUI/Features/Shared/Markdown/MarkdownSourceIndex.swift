import Markdown

/// Resolves Markdown's UTF-8 byte columns without retaining a second copy of the source.
struct MarkdownSourceIndex: Sendable
{
	private let source: String
	private let lineStarts: [String.Index]

	init(_ source: String)
	{
		self.source = source
		let bytes = source.utf8
		lineStarts = bytes.withContiguousStorageIfAvailable
		{
			Self.lineStarts(
				in: $0,
				utf8: bytes
			)
		} ?? Self.lineStarts(
			in: bytes,
			utf8: bytes
		)
	}

	private static func lineStarts<Bytes: Sequence>(
		in bytes: Bytes,
		utf8: String.UTF8View
	) -> [String.Index] where Bytes.Element == UInt8
	{
		var starts = [utf8.startIndex]
		var lineByteCount = 0
		for byte in bytes
		{
			lineByteCount += 1
			if byte == 10
			{
				starts.append(utf8.index(
					starts[starts.count - 1],
					offsetBy: lineByteCount
				))
				lineByteCount = 0
			}
		}
		return starts
	}

	func text(in range: SourceRange?) -> String?
	{
		guard let range
		else
		{
			return nil
		}
		func index(of location: SourceLocation) -> String.Index?
		{
			guard location.line > 0, location.line <= lineStarts.count,
					location.column > 0
			else
			{
				return nil
			}
			return source.utf8.index(
				lineStarts[location.line - 1],
				offsetBy: location.column - 1,
				limitedBy: source.endIndex
			)
		}
		guard let start = index(of: range.lowerBound), let end = index(of: range.upperBound),
				start <= end
		else
		{
			return nil
		}
		return String(
			decoding: source.utf8[start ..< end],
			as: UTF8.self
		)
	}

}
