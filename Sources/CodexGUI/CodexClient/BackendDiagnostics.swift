import Foundation

struct BackendDiagnosticsSnapshot: Equatable, Sendable
{
	let cliVersion: String?
	let exitCode: Int?
	let stderrTail: String
}

/// Keeps a small, process-local stderr tail for an app-server connection.
final class BackendDiagnosticsBuffer: @unchecked Sendable
{
	static let maximumStderrBytes = 8 * 1024

	private let lock = NSLock()
	private var stderrBytes = Data()
	private var cliVersion: String?
	private var exitCode: Int?
	private var generation = UUID()

	@discardableResult
	func beginConnection(cliVersion: String?) -> UUID
	{
		lock.lock()
		defer
		{
			lock.unlock()
		}
		stderrBytes.removeAll(keepingCapacity: true)
		self.cliVersion = cliVersion
		exitCode = nil
		generation = UUID()
		return generation
	}

	func appendStderr(
		_ data: Data,
		for generation: UUID
	)
	{
		guard !data.isEmpty
		else
		{
			return
		}
		lock.lock()
		defer
		{
			lock.unlock()
		}
		guard generation == self.generation
		else
		{
			return
		}

		if data.count >= Self.maximumStderrBytes
		{
			stderrBytes = Data(data.suffix(Self.maximumStderrBytes))
			return
		}

		stderrBytes.append(data)
		let overflow = stderrBytes.count - Self.maximumStderrBytes
		if overflow > 0
		{
			stderrBytes.removeFirst(overflow)
		}
	}

	func recordExitCode(
		_ exitCode: Int32,
		for generation: UUID
	)
	{
		lock.lock()
		defer
		{
			lock.unlock()
		}
		guard generation == self.generation
		else
		{
			return
		}
		self.exitCode = Int(exitCode)
	}

	func snapshot() -> BackendDiagnosticsSnapshot
	{
		lock.lock()
		defer
		{
			lock.unlock()
		}
		let rawText = String(
			decoding: stderrBytes,
			as: UTF8.self
		)
		return BackendDiagnosticsSnapshot(
			cliVersion: cliVersion.map(Self.normalizedMetadata),
			exitCode: exitCode,
			stderrTail: Self.displaySafeText(rawText)
		)
	}

	private static func normalizedMetadata(_ value: String) -> String
	{
		let safeText = displaySafeText(value)
		let words = safeText.components(separatedBy: .whitespacesAndNewlines).filter
		{
			!$0.isEmpty
		}
		return words.joined(separator: " ")
	}

	private static func displaySafeText(_ value: String) -> String
	{
		let withoutTerminalSequences = removingTerminalSequences(from: value)
		let normalized = normalizingControls(in: withoutTerminalSequences)
		return redactRecognizableSecrets(in: normalized)
	}

	private static func removingTerminalSequences(from value: String) -> String
	{
		// Strip complete terminal sequences before removing their control characters.
		return value
			.replacingOccurrences(
				of:
				"(?:\u{001B}\\]|\u{009D})[^\u{0007}\u{001B}\u{009C}]*"
					+ "(?:\u{0007}|\u{001B}\\\\|\u{009C})",
				with: "",
				options: .regularExpression
			)
			.replacingOccurrences(
				of: "(?:\u{001B}\\[|\u{009B})[0-?]*[ -/]*[@-~]",
				with: "",
				options: .regularExpression
			)
	}

	private static func normalizingControls(in value: String) -> String
	{
		let normalizedNewlines = value
			.replacingOccurrences(
				of: "\r\n",
				with: "\n"
			)
			.replacingOccurrences(
				of: "\r",
				with: "\n"
			)
		return normalizedNewlines.unicodeScalars.map
		{
			scalar -> String in
			if scalar == "\n"
			{
				return "\n"
			}
			if scalar == "\t"
			{
				return " "
			}
			if isControl(scalar)
			{
				return ""
			}
			return String(scalar)
		}.joined()
	}

	private static func redactRecognizableSecrets(in value: String) -> String
	{
		let patterns = [
			(
				#"(?i)\b(OPENAI_API_KEY|CODEX_API_KEY|API_KEY|ACCESS_TOKEN|"#
					+ #"REFRESH_TOKEN|PASSWORD|SECRET)\b["']?\s*[:=]\s*"#
					+ #"("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[^\s,;]+)"#,
				"$1=[REDACTED]"
			),
			(#"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+"#, "Bearer [REDACTED]"),
			(#"\bsk-[A-Za-z0-9_-]{12,}\b"#, "[REDACTED_API_KEY]"),
		]

		return patterns.reduce(value)
		{
			result, pattern in
			result.replacingOccurrences(
				of: pattern.0,
				with: pattern.1,
				options: .regularExpression
			)
		}
	}

	private static func isControl(_ scalar: Unicode.Scalar) -> Bool
	{
		scalar.value <= 0x1F || (0x7F ... 0x9F).contains(scalar.value)
	}
}
