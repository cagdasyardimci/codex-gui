import Foundation
import Testing

@testable import CodexGUI

struct GitCommandRunnerTests
{
	@Test func returnsBytesAndExitStatusWithoutApplyingCallerPolicy() throws
	{
		let matching = try GitCommandRunner.run(
			arguments: ["-c", "user.name=runner", "config", "--get", "user.name"],
			maximumBytes: 7
		)
		#expect(matching.bytes == Data("runner\n".utf8))
		#expect(matching.terminationStatus == 0)

		let missing = try GitCommandRunner.run(
			arguments: ["config", "--get-regexp", "^$"],
			maximumBytes: 7
		)
		#expect(missing.bytes.isEmpty)
		#expect(missing.terminationStatus == 1)
	}

	@Test func rejectsOutputBeyondTheCallerLimit() throws
	{
		#expect(throws: GitCommandRunnerError.self)
		{
			try GitCommandRunner.run(
				arguments: ["-c", "user.name=runner", "config", "--get", "user.name"],
				maximumBytes: 6
			)
		}
	}
}
