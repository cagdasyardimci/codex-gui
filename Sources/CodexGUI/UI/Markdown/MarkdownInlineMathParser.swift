import Foundation
import Markdown

/// Shields TeX from CommonMark escapes and emphasis without moving source byte locations.
enum MarkdownInlineMathParser
{
	struct Block
	{
		let placeholder: String
		let math: MarkdownRichBlock
	}

	struct Prepared
	{
		let source: String
		let blocks: [Character: Block]
	}

	private struct TextScope
	{
		let range: Range<Int>
		let end: Int
	}

	static func prepare(
		_ source: String,
		document: Document
	) -> Prepared
	{
		guard source.contains(#"\("#)
		else
		{
			return Prepared(
				source: source,
				blocks: [:]
			)
		}
		let bytes = Array(source.utf8)
		let lineOffsets = [0] + bytes.indices.compactMap
		{
			bytes[$0] == 10 ? $0 + 1 : nil
		}
		func sourceRange(_ markup: any Markup) -> Range<Int>?
		{
			guard let range = markup.range,
					range.lowerBound.line > 0, range.upperBound.line <= lineOffsets.count
			else
			{
				return nil
			}
			let start = lineOffsets[range.lowerBound.line - 1] + range.lowerBound.column - 1
			let end = lineOffsets[range.upperBound.line - 1] + range.upperBound.column - 1
			return start >= 0 && start <= end && end <= bytes.count ? start ..< end : nil
		}
		var scopes: [TextScope] = []
		func visit(
			_ markup: any Markup,
			end: Int?
		)
		{
			if markup is CodeBlock || markup is InlineCode || markup is Image
				|| markup is HTMLBlock || markup is InlineHTML
			{
				return
			}
			var scopeEnd = end
			if markup is Paragraph || markup is Heading || markup is Table.Cell
			{
				scopeEnd = sourceRange(markup)?.upperBound
			}
			if let link = markup as? Link
			{
				if link.isAutolink
				{
					return
				}
				// A label may contain math; its destination and closing brackets stay Markdown.
				scopeEnd = markup.children.compactMap(sourceRange).map(\.upperBound).max()
			}
			if markup is Markdown.Text, let range = sourceRange(markup), let scopeEnd
			{
				scopes.append(TextScope(
					range: range,
					end: scopeEnd
				))
			}
			for child in markup.children
			{
				visit(
					child,
					end: scopeEnd
				)
			}
		}
		visit(
			document,
			end: nil
		)
		var prepared = bytes
		var blocks: [Character: Block] = [:]
		var consumedEnd = 0
		var scalarValue: UInt32 = 0xF0000
		let sourceScalars = Set(source.unicodeScalars)
		for scope in scopes
		{
			var index = max(
				scope.range.lowerBound,
				consumedEnd
			)
			while index + 1 < scope.range.upperBound
			{
				guard isDelimiter(
					bytes,
					at: index,
					suffix: 40
				)
				else
				{
					index += 1
					continue
				}
				var close = index + 2
				while close + 1 < scope.end, bytes[close] != 10, bytes[close] != 13,
						!isDelimiter(
						bytes,
						at: close,
						suffix: 41
						)
				{
					close += 1
				}
				guard close + 1 < scope.end, isDelimiter(
					bytes,
					at: close,
					suffix: 41
				)
				else
				{
					// No opener before this line/scope boundary can find a closer either.
					// Share the scanned boundary across sibling text nodes to avoid rescanning.
					consumedEnd = min(
						scope.end,
						close + 1
					)
					index = consumedEnd
					continue
				}
				let payload = String(
					decoding: bytes[index + 2 ..< close],
					as: UTF8.self
				)
				guard !payload.trimmingCharacters(in: .whitespaces).isEmpty
				else
				{
					index = close + 2
					continue
				}
				while scalarValue < 0xFFFFE,
						let scalar = Unicode.Scalar(scalarValue),
						sourceScalars.contains(scalar)
				{
					scalarValue += 1
				}
				guard scalarValue < 0xFFFFE, let scalar = Unicode.Scalar(scalarValue)
				else
				{
					break
				}
				let marker = Character(scalar)
				let end = close + 2
				let placeholder = String(marker) + String(
					repeating: "m",
					count: end - index - 4
				)
				blocks[marker] = Block(
					placeholder: placeholder,
					math: MarkdownRichBlock(
						kind: .math,
						source: String(
							decoding: bytes[index ..< end],
							as: UTF8.self
						),
						payload: payload,
						isInline: true
					)
				)
				prepared.replaceSubrange(
					index ..< end,
					with: placeholder.utf8
				)
				scalarValue += 1
				consumedEnd = end
				index = end
			}
		}
		return Prepared(
			source: String(
				decoding: prepared,
				as: UTF8.self
			),
			blocks: blocks
		)
	}

	private static func isDelimiter(
		_ bytes: [UInt8],
		at index: Int,
		suffix: UInt8
	) -> Bool
	{
		guard index + 1 < bytes.count, bytes[index] == 92, bytes[index + 1] == suffix
		else
		{
			return false
		}
		var preceding = index
		while preceding > 0, bytes[preceding - 1] == 92
		{
			preceding -= 1
		}
		return (index - preceding).isMultiple(of: 2)
	}
}
