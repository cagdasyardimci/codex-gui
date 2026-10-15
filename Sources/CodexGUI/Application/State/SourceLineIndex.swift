import Foundation

/// Logical source lines use AppKit's UTF-16 offsets and retain a trailing empty document line.
struct SourceLineIndex: Equatable, Sendable
{
	private let text: String
	let lineStarts: [Int]
	let utf16Length: Int

	init(_ text: String)
	{
		self.text = text
		let units = Array(text.utf16)
		utf16Length = units.count
		var starts = [0]
		var offset = 0
		while offset < units.count
		{
			let unit = units[offset]
			offset += 1
			if unit == 13, offset < units.count, units[offset] == 10
			{
				offset += 1
			}
			if Self.isLineEnding(unit)
			{
				starts.append(offset)
			}
		}
		lineStarts = starts
	}

	var lines: [String]
	{
		let source = text as NSString
		return lineStarts.indices.map
		{
			source.substring(with: contentRange(
				atLineIndex: $0,
				in: source
			))
		}
	}

	func contentRange(atLineIndex index: Int) -> NSRange
	{
		contentRange(
			atLineIndex: index,
			in: text as NSString
		)
	}

	private func contentRange(
		atLineIndex index: Int,
		in source: NSString
	) -> NSRange
	{
		let start = lineStarts[index]
		var end = index + 1 < lineStarts.count ? lineStarts[index + 1] : utf16Length
		if end > start, Self.isLineEnding(source.character(at: end - 1))
		{
			let lastUnit = source.character(at: end - 1)
			end -= 1
			if lastUnit == 10, end > start, source.character(at: end - 1) == 13
			{
				end -= 1
			}
		}
		return NSRange(
			location: start,
			length: end - start
		)
	}

	func lineNumber(atUTF16Offset offset: Int) -> Int
	{
		let boundedOffset = min(
			max(
				0,
				offset
			),
			utf16Length
		)
		var lower = 0
		var upper = lineStarts.count
		while lower < upper
		{
			let middle = (lower + upper) / 2
			if lineStarts[middle] <= boundedOffset
			{
				lower = middle + 1
			}
			else
			{
				upper = middle
			}
		}
		return lower
	}

	private static func isLineEnding(_ unit: UInt16) -> Bool
	{
		unit == 10 || unit == 13 || unit == 0x2028 || unit == 0x2029
	}
}
