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
