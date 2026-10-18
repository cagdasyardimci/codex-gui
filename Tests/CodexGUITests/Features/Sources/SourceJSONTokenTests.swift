import Foundation
import Testing

@testable import CodexGUI

struct SourceJSONTokenTests
{
	@Test(arguments: [
		#"{"key":"escaped \"true\" 1","flag":true,"none":null,"n":-12.5e+2}"#,
		"{\"🧭e\u{301}\"\u{2028}\u{85}\t: \"雪\", \"literal\": false}",
		"{\"\u{301}key\":\"\u{1D185}value\",\"colon\":\u{301} false}",
		"[\"value\", \"last\"   ]",
		"\"unfinished \\\" string true 42",
		"true false null trueish -0 3.1E-2 5",
		"",
	])
	func colorRolesAndUTF16RangesMatchThePreviousClassifier(_ source: String) throws
	{
		#expect(SourceJSONToken.tokens(in: source) == (try previousTokens(in: source)))
	}

	@Test func manySmallStringValuesPreserveKeyAndValueRoles() throws
	{
		let source = "{" + (0 ..< 1_000).map
		{
			"\"key\($0)\":\"value\($0)\""
		}.joined(separator: ",") + "}"
		let tokens = SourceJSONToken.tokens(in: source)
		#expect(tokens.count == 2_000)
		#expect(tokens == (try previousTokens(in: source)))
		#expect(tokens.enumerated().allSatisfy
		{
			$0.element.style == ($0.offset.isMultiple(of: 2) ? .key : .string)
		})
	}

	private func previousTokens(in text: String) throws -> [SourceJSONToken]
	{
		let expression = try NSRegularExpression(
			pattern: #""(?:\\.|[^"\\])*"|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|\b(?:true|false|null)\b"#
		)
		let source = text as NSString
		return expression.matches(
			in: text,
			range: NSRange(
				location: 0,
				length: source.length
			)
		).map
		{
			match in
			let token = source.substring(with: match.range)
			let style: SourceJSONToken.Style
			if token.hasPrefix("\"")
			{
				let tail = source.substring(from: NSMaxRange(match.range))
					.trimmingCharacters(in: .whitespacesAndNewlines)
				style = tail.hasPrefix(":") ? .key : .string
			}
			else if token == "true" || token == "false" || token == "null"
			{
				style = .literal
			}
			else
			{
				style = .number
			}
			return SourceJSONToken(
				range: match.range,
				style: style
			)
		}
	}
}
