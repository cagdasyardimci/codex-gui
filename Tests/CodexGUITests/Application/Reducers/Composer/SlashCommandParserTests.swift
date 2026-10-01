import Foundation
import Testing

@testable import CodexGUI

@Suite
struct SlashCommandParserTests
{
	@Test(arguments: [
		"",
		"ordinary text",
		"Please use /plan later",
		"https://example.com/plan",
		"/Users/person/file.swift",
		"/tmp/foo",
		"/file.swift",
		"/plan/child",
		"/Users",
		"/tmp",
		"/etc",
		"/usr contains binaries",
		"/Applications",
		"/Users/person/My File.swift",
		"/tmp/My Folder/file.txt",
		"/plan:",
		"/plan()",
		"/π",
		"/",
		"//server/path",
		"//",
		"```\n/plan do something\n```",
		"`/plan`",
		"\n/plan pasted text",
	])
	func ordinaryTextIsPreserved(_ draft: String)
	{
		#expect(SlashCommandParser.parse(draft) == .text(draft))
	}

	@Test func literalEscapeBypassesBothRecognitionAndUnknownCommandErrors()
	{
		#expect(SlashCommandParser.parse("//plan a\nb") == .text("/plan a\nb"))
		#expect(SlashCommandParser.parse("  //unknown thing") == .text("  /unknown thing"))
		#expect(SlashCommandParser.parse("//delete") == .text("/delete"))
		#expect(SlashCommandParser.parse("//customroot") == .text("/customroot"))
	}

	@Test func inlinePlanPreservesEveryCharacterAfterOneSeparator() throws
	{
		let arguments = " 🧪 explain this\n\n```swift\nlet x = 1\n```\n  "
		let invocation = try command("\t /PLAN " + arguments)
		#expect(invocation.id == .plan)
		#expect(invocation.arguments == arguments)
		#expect(try command("/plan\nline one\nline two").arguments == "line one\nline two")
		#expect(try command("/plan\r\nline one").arguments == "line one")
		#expect(try command("/plan").arguments.isEmpty)
		#expect(try command("/plan \n\t").trimmedArguments.isEmpty)
	}

	@Test func renamePreservesFreeformUnicodeWithoutShellUnquoting() throws
	{
		let invocation = try command("/rename  Çağdaş 🧪 \"quoted name\"\nSecond line  ")
		#expect(invocation.id == .rename)
		#expect(invocation.arguments == " Çağdaş 🧪 \"quoted name\"\nSecond line  ")
		#expect(invocation.trimmedArguments == "Çağdaş 🧪 \"quoted name\"\nSecond line")
		#expect(try command("/rename").id == .rename)
		#expect(try command("/rename \n ").trimmedArguments.isEmpty)
	}

	@Test func noArgumentCommandsRejectAccidentalPrompts() throws
	{
		for descriptor in SlashCommandRegistry.commands where descriptor.argumentKind == .none
		{
			#expect(try command("/\(descriptor.name) \t\n").id == descriptor.id)
			#expect(try error("/\(descriptor.name) please do this").command == descriptor.id)
		}
	}

	@Test func identifiersAreSingleTokensAndCatalogValidationStaysWithRuntime() throws
	{
		for id in [SlashCommandID.resume, .model, .reasoning]
		{
			#expect(try command("/\(id.rawValue)").id == id)
			#expect(try command("/\(id.rawValue) future-value").trimmedArguments == "future-value")
			#expect(try error("/\(id.rawValue) one two").command == id)
			#expect(try error("/\(id.rawValue) one\ntwo").command == id)
		}
	}

	@Test func fixedOptionsRejectUnsupportedAndAmbiguousValues() throws
	{
		#expect(try command("/fast").trimmedArguments.isEmpty)
		#expect(try command("/fast on").trimmedArguments == "on")
		#expect(try command("/fast off \n").trimmedArguments == "off")
		#expect(try error("/fast ON").usage == "/fast [on|off]")
		#expect(try error("/fast on off").command == .fast)
		for preset in ["", "ask", "auto", "full"]
		{
			#expect(try command("/permissions " + preset).trimmedArguments == preset)
		}
		#expect(try error("/permissions unrestricted").command == .permissions)
	}

	@Test func reviewTargetGrammarHasExplicitTargetAndValueBoundaries() throws
	{
		for target in ["", "uncommitted", "base main", "commit abc123", "custom inspect\nthis"]
		{
			#expect(try command("/review " + target).trimmedArguments == target)
		}
		for target in ["main", "base", "base main other", "commit", "commit abc title", "custom"]
		{
			#expect(try error("/review " + target).command == .review)
		}
	}

	@Test func unknownCommandProvidesActionableLocalError() throws
	{
		let failure = try error("/unknown argument")
		#expect(failure.command == nil)
		#expect(failure.message.contains("Unknown command '/unknown'"))
		#expect(failure.message.contains("'//unknown'"))
		#expect(failure.usage == nil)
	}

	@Test func completionReplacesWholeTokenAndPreservesUnicodeArguments() throws
	{
		let draft = "\t /pla 🧪\nÇağdaş"
		let query = try #require(SlashCommandParser.completionQuery(
			in: draft,
			selectedRange: NSRange(
				location: 6,
				length: 0
			)
		))
		#expect(query.prefix == "pla")
		#expect(query.tokenRange == NSRange(
			location: 2,
			length: 4
		))
		#expect((draft as NSString).replacingCharacters(
			in: query.tokenRange,
			with: "/plan"
		)
			== "\t /plan 🧪\nÇağdaş")
		let middle = try #require(SlashCommandParser.completionQuery(
			in: "/PLAN 🧪",
			selectedRange: NSRange(
				location: 3,
				length: 0
			)
		))
		#expect(middle.prefix == "pl")
		#expect(middle.tokenRange == NSRange(
			location: 0,
			length: 5
		))
		#expect(SlashCommandParser.completionQuery(
			in: "/",
			selectedRange: NSRange(
				location: 1,
				length: 0
			)
		)?.prefix == "")
	}

	@Test func completionRejectsSelectionsInvalidUTF16AndNonleadingSlashTokens()
	{
		let draft = "/plan 🧪"
		for selection in [
			NSRange(
				location: 0,
				length: 0
			),
			NSRange(
				location: 1,
				length: 2
			),
			NSRange(
				location: 6,
				length: 0
			),
			NSRange(
				location: 7,
				length: 0
			),
			NSRange(
				location: 8,
				length: 0
			),
			NSRange(
				location: 99,
				length: 0
			),
			NSRange(
				location: NSNotFound,
				length: 0
			),
			NSRange(
				location: -1,
				length: 0
			),
		]
		{
			#expect(SlashCommandParser.completionQuery(
				in: draft,
				selectedRange: selection
			) == nil)
		}
		for text in ["text /pla", "/tmp/file", "/π", "//plan", "```\n/pla", "\n/pla"]
		{
			#expect(SlashCommandParser.completionQuery(
				in: text,
				selectedRange: NSRange(
					location: text.utf16.count,
					length: 0
				)
			) == nil)
		}
	}

	private func command(_ draft: String) throws -> SlashCommandInvocation
	{
		let result = SlashCommandParser.parse(draft)
		guard case .command(let invocation) = result
		else
		{
			Issue.record("Expected command, got \(result)")
			throw ParseExpectationFailure.unexpectedResult
		}
		return invocation
	}

	private func error(_ draft: String) throws -> SlashCommandError
	{
		let result = SlashCommandParser.parse(draft)
		guard case .error(let failure) = result
		else
		{
			Issue.record("Expected command error, got \(result)")
			throw ParseExpectationFailure.unexpectedResult
		}
		return failure
	}

	private enum ParseExpectationFailure: Error
	{
		case unexpectedResult
	}
}
