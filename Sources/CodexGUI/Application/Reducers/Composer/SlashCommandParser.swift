import Foundation

struct SlashCommandInvocation: Equatable, Sendable
{
	let descriptor: SlashCommandDescriptor
	let arguments: String

	var id: SlashCommandID
	{
		descriptor.id
	}
	var trimmedArguments: String
	{
		arguments.trimmingCharacters(in: .whitespacesAndNewlines)
	}
}

struct SlashCommandError: Equatable, Sendable
{
	let message: String
	let command: SlashCommandID?
	let usage: String?
}

enum SlashCommandParseResult: Equatable, Sendable
{
	case text(String)
	case command(SlashCommandInvocation)
	case error(SlashCommandError)
}

struct SlashCommandCompletionQuery: Equatable, Sendable
{
	let prefix: String
	/// UTF-16 range covering the whole slash token, including its leading slash.
	let tokenRange: NSRange
}

/// Grammar: optional leading spaces/tabs, then `/name` and a whitespace separator.
/// Names use ASCII letters, digits and hyphens; path/punctuation tokens remain ordinary text.
/// Conventional root-directory names are literal paths, even without a trailing slash.
/// Argument text loses exactly one separating Character; all remaining text is preserved.
/// There is no shell quoting or escaping. `//name` sends literal `/name` text.
enum SlashCommandParser
{
	private static let rootDirectoryNames: Set<String> = [
		"Applications",
		"Library",
		"System",
		"Users",
		"Volumes",
		"bin",
		"cores",
		"dev",
		"etc",
		"home",
		"mnt",
		"opt",
		"private",
		"sbin",
		"tmp",
		"usr",
		"var",
	]

	static func parse(_ draft: String) -> SlashCommandParseResult
	{
		let start = commandStart(in: draft)
		guard start < draft.endIndex, draft[start] == "/"
		else
		{
			return .text(draft)
		}

		let nameStart = draft.index(after: start)
		if nameStart < draft.endIndex, draft[nameStart] == "/"
		{
			let literalNameStart = draft.index(after: nameStart)
			let literalTokenEnd = draft[literalNameStart...]
				.firstIndex(where: \.isWhitespace) ?? draft.endIndex
			let literalName = String(draft[literalNameStart ..< literalTokenEnd])
			guard isCommandName(
				literalName,
				allowingEmpty: false
			)
			else
			{
				return .text(draft)
			}
			var literal = draft
			literal.remove(at: start)
			return .text(literal)
		}

		let tokenEnd = draft[nameStart...].firstIndex(where: \.isWhitespace) ?? draft.endIndex
		let name = String(draft[nameStart ..< tokenEnd])
		guard isCommandName(
			name,
			allowingEmpty: false
		)
		else
		{
			return .text(draft)
		}
		guard let descriptor = SlashCommandRegistry.descriptor(for: name)
		else
		{
			guard !rootDirectoryNames.contains(name)
			else
			{
				return .text(draft)
			}
			return .error(SlashCommandError(
				message: "Unknown command '/\(name)'. Choose a command, "
					+ "or use '//\(name)' to send it as text.",
				command: nil,
				usage: nil
			))
		}

		let arguments = tokenEnd < draft.endIndex
			? String(draft[draft.index(after: tokenEnd)...]) : ""
		let invocation = SlashCommandInvocation(
			descriptor: descriptor,
			arguments: arguments
		)
		guard accepts(
			invocation.trimmedArguments,
			kind: descriptor.argumentKind
		)
		else
		{
			return .error(SlashCommandError(
				message: "Invalid arguments for '/\(descriptor.name)'. Use \(descriptor.usage).",
				command: descriptor.id,
				usage: descriptor.usage
			))
		}
		return .command(invocation)
	}

	/// Completion is available only while a collapsed caret is within the initial token.
	/// Both selection boundaries must be valid String indices, including UTF-16 surrogate pairs.
	static func completionQuery(
		in draft: String,
		selectedRange: NSRange
	) -> SlashCommandCompletionQuery?
	{
		guard selectedRange.length == 0, selectedRange.location >= 0,
				selectedRange.location <= draft.utf16.count
		else
		{
			return nil
		}
		guard let selection = Range(
			selectedRange,
			in: draft
		)
		else
		{
			return nil
		}
		let start = commandStart(in: draft)
		guard start < draft.endIndex, draft[start] == "/"
		else
		{
			return nil
		}
		let nameStart = draft.index(after: start)
		let tokenEnd = draft[nameStart...].firstIndex(where: \.isWhitespace) ?? draft.endIndex
		let name = String(draft[nameStart ..< tokenEnd])
		guard isCommandName(
			name,
			allowingEmpty: true
		),
			selection.lowerBound >= nameStart, selection.lowerBound <= tokenEnd
		else
		{
			return nil
		}
		return SlashCommandCompletionQuery(
			prefix: String(draft[nameStart ..< selection.lowerBound]).lowercased(),
			tokenRange: NSRange(
				start ..< tokenEnd,
				in: draft
			)
		)
	}

	private static func commandStart(in draft: String) -> String.Index
	{
		draft.firstIndex
		{
			$0 != " " && $0 != "\t"
		} ?? draft.endIndex
	}

	private static func isCommandName(
		_ name: String,
		allowingEmpty: Bool
	) -> Bool
	{
		guard let first = name.utf8.first
		else
		{
			return allowingEmpty
		}
		guard isASCIILetter(first)
		else
		{
			return false
		}
		return name.utf8.allSatisfy
		{
			isASCIILetter($0) || (48 ... 57).contains($0) || $0 == 45
		}
	}

	private static func isASCIILetter(_ byte: UInt8) -> Bool
	{
		(65 ... 90).contains(byte) || (97 ... 122).contains(byte)
	}

	private static func accepts(
		_ arguments: String,
		kind: SlashCommandArgumentKind
	) -> Bool
	{
		switch kind
		{
		case .none: arguments.isEmpty
		case .optionalIdentifier: !arguments.contains(where: \.isWhitespace)
		case .optionalText, .optionalPrompt: true
		case .optionalChoice(let choices): arguments.isEmpty || choices.contains(arguments)
		case .reviewTarget: acceptsReviewTarget(arguments)
		}
	}

	private static func acceptsReviewTarget(_ arguments: String) -> Bool
	{
		if arguments.isEmpty || arguments == "uncommitted"
		{
			return true
		}
		let targetEnd = arguments.firstIndex(where: \.isWhitespace) ?? arguments.endIndex
		let target = String(arguments[..<targetEnd])
		let value = arguments[targetEnd...].trimmingCharacters(in: .whitespacesAndNewlines)
		guard !value.isEmpty
		else
		{
			return false
		}
		switch target
		{
		case "base", "commit": return !value.contains(where: \.isWhitespace)
		case "custom": return true
		default: return false
		}
	}
}
