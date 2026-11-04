import AppKit
import Highlighter
import JavaScriptCore

/// Applies measured code-theme colors to Highlight.js token classes.
@MainActor
enum PresetSyntaxRenderer
{
	private static var context: JSContext?
	private static var attemptedInitialization = false
	private static let tokens = try! NSRegularExpression(
		pattern: #"<span class="([^"]+)">|</span>|"#
			+ #"&(?:amp|lt|gt|quot|apos|#(?:x[0-9a-fA-F]+|[0-9]+));"#
	)

	static func highlight(
		_ source: String,
		language: String,
		themeID: String
	) -> NSAttributedString?
	{
		guard let theme = MeasuredCodeThemeColors.themes[themeID]
		else
		{
			return nil
		}
		return highlight(
			source,
			language: language,
			theme: theme,
			markdownJavaScript: false
		)
	}

	static func markdownDark(
		_ source: String,
		language: String,
		foreground: UInt32
	) -> NSAttributedString?
	{
		let theme = MeasuredCodeThemeColors.markdownDark(foreground: foreground)
		return highlight(
			source,
			language: language,
			theme: theme,
			markdownJavaScript: language == "javascript"
		)
	}

	static func highlight(
		_ source: String,
		language: String,
		theme: MeasuredCodeThemeColors.Theme,
		markdownJavaScript: Bool
	) -> NSAttributedString?
	{
		guard let context = javascriptContext(),
				let hljs = context.objectForKeyedSubscript("hljs")
		else
		{
			return nil
		}
		context.exception = nil
		guard let result = hljs.invokeMethod(
			"highlight",
			withArguments: [source, ["language": language, "ignoreIllegals": true]]
		), context.exception == nil,
		let html = result.objectForKeyedSubscript("value")?.toString(), html != "undefined"
		else
		{
			return nil
		}
		let output = NSMutableAttributedString(string: "")
		let input = html as NSString
		var offset = 0
		var stack: [[String]] = []
		func append(_ value: String)
		{
			guard !value.isEmpty
			else
			{
				return
			}
			if markdownJavaScript && stack.isEmpty
			{
				appendJavaScriptPlain(
					value,
					to: output,
					theme: theme
				)
				return
			}
			if language == "swift" && stack.isEmpty
			{
				appendSwiftPlain(
					value,
					to: output,
					theme: theme
				)
				return
			}
			let role = stack.reversed().compactMap(role(for:)).first
			let hex = role.flatMap
			{
				theme.colors[$0]
			} ?? theme.foreground
			guard let color = AppKitColorResolution.hexColor(hex)
			else
			{
				return
			}
			output.append(NSAttributedString(
				string: value,
				attributes: [.foregroundColor: color]
			))
		}
		for match in tokens.matches(
			in: html,
			range: NSRange(
				location: 0,
				length: input.length
			)
		)
		{
			append(input.substring(with: NSRange(
				location: offset,
				length: match.range.location - offset
			)))
			let token = input.substring(with: match.range)
			if token.hasPrefix("<span "), match.range(at: 1).location != NSNotFound
			{
				stack
					.append(input.substring(with: match.range(at: 1)).split(separator: " ")
						.map(String.init))
			}
			else if token == "</span>"
			{
				guard !stack.isEmpty
				else
				{
					return nil
				}
				stack.removeLast()
			}
			else
			{
				guard let decoded = decode(token)
				else
				{
					return nil
				}
				append(decoded)
			}
			offset = NSMaxRange(match.range)
		}
		append(input.substring(from: offset))
		guard stack.isEmpty, Data(output.string.utf8) == Data(source.utf8)
		else
		{
			return nil
		}
		return output
	}

	private static func appendJavaScriptPlain(
		_ value: String,
		to output: NSMutableAttributedString,
		theme: MeasuredCodeThemeColors.Theme
	)
	{
		let text = value as NSString
		let rendered = NSMutableAttributedString(
			string: value,
			attributes: [.foregroundColor: AppKitColorResolution.hexColor(theme.foreground)!]
		)
		let pattern =
			try! NSRegularExpression(pattern: #"[A-Za-z_$][A-Za-z0-9_$]*|[=+*/%!?<>|&^~:-]+"#)
		for match in pattern.matches(
			in: value,
			range: NSRange(
				location: 0,
				length: text.length
			)
		)
		{
			let token = text.substring(with: match.range)
			let role: String
			if token.first?.isLetter == true || token.first == "_" || token.first == "$"
			{
				role = token.count == 1 && token.first?.isUppercase == true ? "number" : "variable"
			}
			else
			{
				role = "operator"
			}
			if let hex = theme.colors[role], let tokenColor = AppKitColorResolution.hexColor(hex)
			{
				rendered.addAttribute(
					.foregroundColor,
					value: tokenColor,
					range: match.range
				)
			}
		}
		output.append(rendered)
	}

	// Highlight.js leaves Swift argument labels unclassified. They consume the same
	// variable role as other named values, without changing string/comment spans.
	private static let swiftLabels =
		try! NSRegularExpression(pattern: #"\b[A-Za-z_][A-Za-z0-9_]*(?=\s*:)"#)
	private static func appendSwiftPlain(
		_ value: String,
		to output: NSMutableAttributedString,
		theme: MeasuredCodeThemeColors.Theme
	)
	{
		let text = NSMutableAttributedString(
			string: value,
			attributes: [.foregroundColor: AppKitColorResolution.hexColor(theme.foreground)!]
		)
		if let hex = theme.colors["variable"], let color = AppKitColorResolution.hexColor(hex)
		{
			for match in swiftLabels.matches(
				in: value,
				range: NSRange(
					location: 0,
					length: text.length
				)
			)
			{
				text.addAttribute(
					.foregroundColor,
					value: color,
					range: match.range
				)
			}
		}
		output.append(text)
	}

	private static func role(for classes: [String]) -> String?
	{
		if classes.contains("hljs-title") && classes.contains("function_")
		{
			return "function"
		}
		if classes.contains("hljs-title") && classes.contains("class_")
		{
			return "type"
		}
		let roles = [
			"keyword": "keyword",
			"operator": "operator",
			"comment": "comment",
			"string": "string",
			"number": "number",
			"literal": "boolean",
			"variable": "variable",
			"property": "property",
			"attr": "property",
			"attribute": "attribute",
			"type": "type",
			"built_in": "variable.special",
			"meta": "preproc",
			"tag": "tag",
			"name": "tag",
			"regexp": "string.regex",
			"symbol": "constant",
			"title": "title",
			"params": "variable.parameter",
			"punctuation": "punctuation",
		]
		return classes.compactMap
		{
			token in token.hasPrefix("hljs-") ? roles[String(token.dropFirst(5))] : nil
		}.first
	}

	private static func decode(_ entity: String) -> String?
	{
		let named = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'"]
		if let value = named[entity]
		{
			return value
		}
		guard entity.hasPrefix("&#"), entity.hasSuffix(";")
		else
		{
			return nil
		}
		let body = entity.dropFirst(2).dropLast()
		let isHex = body.first == "x"
		guard let value = UInt32(
			isHex ? body.dropFirst() : body[...],
			radix: isHex ? 16 : 10
		),
			let scalar = UnicodeScalar(value)
		else
		{
			return nil
		}
		return String(scalar)
	}

	private static func javascriptContext() -> JSContext?
	{
		if attemptedInitialization
		{
			return context
		}
		attemptedInitialization = true
		let roots = [
			Bundle.main.resourceURL,
			Bundle.main.bundleURL,
			Bundle.main.executableURL?.deletingLastPathComponent(),
			Bundle.module.resourceURL,
			Bundle.module.bundleURL.deletingLastPathComponent(),
		].compactMap
		{
			$0
		}
		for root in roots
		{
			let bundleURL = root.appendingPathComponent("Highlighter_Highlighter.bundle")
			let paths = [
				Bundle(url: bundleURL)?.url(
					forResource: "highlight.min",
					withExtension: "js"
				),
				bundleURL.appendingPathComponent("highlight.min.js"),
				bundleURL.appendingPathComponent("Contents/Resources/highlight.min.js"),
			].compactMap
			{
				$0
			}
			for url in paths
			{
				guard let js = try? String(
					contentsOf: url,
					encoding: .utf8
				),
					let candidate = JSContext()
				else
				{
					continue
				}
				candidate.evaluateScript(js)
				if candidate.exception == nil,
					let value = candidate.objectForKeyedSubscript("hljs"), !value.isUndefined
				{
					context = candidate
					return candidate
				}
			}
		}
		return nil
	}
}
