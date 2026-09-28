import Foundation
import Testing

@testable import CodexGUI

struct BackendDiagnosticsTests
{
	@Test func stderrTailIsBoundedAndKeepsTheMostRecentBytes()
	{
		let diagnostics = BackendDiagnosticsBuffer()
		let generation = diagnostics.beginConnection(cliVersion: "codex-cli 0.153.2")
		diagnostics.appendStderr(
			Data(
				repeating: 0x61,
				count: 8 * 1024
			),
			for: generation
		)
		diagnostics.appendStderr(
			Data("tail".utf8),
			for: generation
		)

		let snapshot = diagnostics.snapshot()
		#expect(snapshot.stderrTail.utf8.count == BackendDiagnosticsBuffer.maximumStderrBytes)
		#expect(snapshot.stderrTail.hasSuffix("tail"))
	}

	@Test func fragmentedUtf8IsDecodedAfterAllBytesArrive()
	{
		let diagnostics = BackendDiagnosticsBuffer()
		let generation = diagnostics.beginConnection(cliVersion: "codex-cli 0.153.2")
		let bytes = Array("status: café 🧪".utf8)
		diagnostics.appendStderr(
			Data(bytes.prefix(12)),
			for: generation
		)
		diagnostics.appendStderr(
			Data(bytes.dropFirst(12).prefix(2)),
			for: generation
		)
		diagnostics.appendStderr(
			Data(bytes.dropFirst(14)),
			for: generation
		)

		#expect(diagnostics.snapshot().stderrTail == "status: café 🧪")
	}

	@Test func snapshotNormalizesControlsAndRedactsRecognizableCredentials()
	{
		let diagnostics = BackendDiagnosticsBuffer()
		let generation = diagnostics.beginConnection(cliVersion: "codex-cli\u{1b}[31m 0.153.2")
		let output =
			"\u{1b}[31mOPENAI_API_KEY=sk-testsecret123456\r\n"
				+ "Authorization: Bearer abc.def-123\tready\u{7}"
		diagnostics.appendStderr(
			Data(output.utf8),
			for: generation
		)

		let snapshot = diagnostics.snapshot()
		#expect(snapshot.cliVersion == "codex-cli 0.153.2")
		#expect(!snapshot.stderrTail.contains("[31m"))
		#expect(snapshot.stderrTail.contains("OPENAI_API_KEY=[REDACTED]"))
		#expect(snapshot.stderrTail.contains("Authorization: Bearer [REDACTED] ready"))
		#expect(!snapshot.stderrTail.contains("sk-testsecret123456"))
		#expect(!snapshot.stderrTail.contains("abc.def-123"))
		#expect(
			!snapshot.stderrTail.unicodeScalars.contains(where:
				{
					isControl($0) && $0 != "\n"
				})
		)
	}

	@Test func versionStripsTerminalLinksAndRedactsQuotedCredentials()
	{
		let diagnostics = BackendDiagnosticsBuffer()
		diagnostics.beginConnection(
			cliVersion:
			"\u{1b}]8;;https://example.com\u{7}codex-cli\u{1b}]8;;\u{1b}\\"
				+ " \u{9b}32m0.153.2\u{1b}[0m\nPASSWORD=\"two words\""
		)

		#expect(diagnostics.snapshot().cliVersion == "codex-cli 0.153.2 PASSWORD=[REDACTED]")
	}

	@Test func quotedAssignmentsRedactTheEntireValue()
	{
		let diagnostics = BackendDiagnosticsBuffer()
		let generation = diagnostics.beginConnection(cliVersion: "codex-cli 0.153.2")
		diagnostics.appendStderr(
			Data(
				(
					#"{"API_KEY": "first second", "PASSWORD": "escaped \"quote\" "#
						+ #"secret"} SECRET='third fourth' ready"#
				)
				.utf8
			),
			for: generation
		)

		let text = diagnostics.snapshot().stderrTail
		for word in ["first", "second", "escaped", "quote", "secret", "third", "fourth"]
		{
			#expect(!text.contains(word))
		}
		#expect(text.contains("ready"))
		#expect(text.components(separatedBy: "[REDACTED]").count == 4)
	}

	@Test func newConnectionResetsTailAndExitMetadata()
	{
		let diagnostics = BackendDiagnosticsBuffer()
		let previousGeneration = diagnostics.beginConnection(cliVersion: "codex-cli 0.153.2")
		diagnostics.appendStderr(
			Data("previous failure".utf8),
			for: previousGeneration
		)
		diagnostics.recordExitCode(
			7,
			for: previousGeneration
		)

		let currentGeneration = diagnostics.beginConnection(cliVersion: "codex-cli 0.154.0")
		diagnostics.appendStderr(
			Data("stale".utf8),
			for: previousGeneration
		)
		diagnostics.recordExitCode(
			9,
			for: previousGeneration
		)
		diagnostics.appendStderr(
			Data("current".utf8),
			for: currentGeneration
		)
		let snapshot = diagnostics.snapshot()

		#expect(snapshot.cliVersion == "codex-cli 0.154.0")
		#expect(snapshot.exitCode == nil)
		#expect(snapshot.stderrTail == "current")
	}

	@Test func snapshotIncludesExitCode()
	{
		let diagnostics = BackendDiagnosticsBuffer()
		let generation = diagnostics.beginConnection(cliVersion: "codex-cli 0.153.2")
		diagnostics.recordExitCode(
			9,
			for: generation
		)

		#expect(diagnostics.snapshot().exitCode == 9)
	}

	private func isControl(_ scalar: Unicode.Scalar) -> Bool
	{
		scalar.value <= 0x1F || (0x7F ... 0x9F).contains(scalar.value)
	}
}
