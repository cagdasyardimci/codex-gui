import Foundation

/// Limited syntax filtering, not an AST: only unindented, single-line Swift module imports
/// and Python import/from statements. Multiline imports and other languages remain visible.
struct GitDiffImportMatcher
{
	private static let swiftExpression = try? NSRegularExpression(
		pattern: #"^(?:@testable |@_exported |@_implementationOnly )?import "#
			+ #"[A-Za-z_][A-Za-z0-9_.]*\s*$"#
	)
	private static let pythonExpression: NSRegularExpression? =
	{
		let alias = #"(?: as [A-Za-z_][A-Za-z0-9_]*)?"#
		let module = #"[A-Za-z_][A-Za-z0-9_.]*"# + alias
		let name = #"[A-Za-z_][A-Za-z0-9_]*"# + alias
		return try? NSRegularExpression(
			pattern: "^(?:import " + module + "(?:, " + module + ")*"
				+ #"|from [A-Za-z_.][A-Za-z0-9_.]* import (?:\*|"#
				+ name + "(?:, " + name + #")*))\s*$"#
		)
	}()

	private let expression: NSRegularExpression

	init?(path: String)
	{
		let expression: NSRegularExpression?
		switch URL(fileURLWithPath: path).pathExtension.lowercased()
		{
		case "swift": expression = Self.swiftExpression
		case "py", "pyw": expression = Self.pythonExpression
		default: return nil
		}
		guard let expression
		else
		{
			return nil
		}
		self.expression = expression
	}

	func matches(_ text: String) -> Bool
	{
		expression.firstMatch(
			in: text,
			range: NSRange(
				text.startIndex ..< text.endIndex,
				in: text
			)
		) != nil
	}
}
