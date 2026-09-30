import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct CheckoutIdentityTests
{
	@Test func defaultServiceResumeAcceptsAliasesAndRejectsAnotherDirectory() async throws
	{
		let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(
			at: root,
			withIntermediateDirectories: true
		)
		defer
		{
			try? FileManager.default.removeItem(at: root)
		}
		let checkout = root.appendingPathComponent(
			"checkout",
			isDirectory: true
		)
		let other = root.appendingPathComponent(
			"other",
			isDirectory: true
		)
		let alias = root.appendingPathComponent(
			"alias",
			isDirectory: true
		)
		try FileManager.default.createDirectory(
			at: checkout,
			withIntermediateDirectories: true
		)
		try FileManager.default.createDirectory(
			at: other,
			withIntermediateDirectories: true
		)
		try FileManager.default.createSymbolicLink(
			at: alias,
			withDestinationURL: checkout
		)
		let service = ResumeService(cwd: alias.path)

		let detail = try await service.resumeThread(
			id: "thread",
			expectedDirectory: checkout
		)
		#expect(detail.summary.cwd == alias.path)
		do
		{
			_ = try await service.resumeThread(
				id: "thread",
				expectedDirectory: other
			)
			Issue.record("Default resume accepted another checkout")
		}
		catch let error as AppServerError
		{
			guard case .protocolError = error
			else
			{
				throw error
			}
		}
	}

	@Test func missingAndRelativeReportedPathsAreRejected() throws
	{
		let checkout = URL(fileURLWithPath: "/tmp/checkout")
		#expect(throws: AppServerError.self)
		{
			try CheckoutIdentity.validate(
				cwd: "",
				expectedDirectory: checkout
			)
		}
		#expect(throws: AppServerError.self)
		{
			try CheckoutIdentity.validate(
				cwd: "tmp/checkout",
				expectedDirectory: checkout
			)
		}
		try CheckoutIdentity.validate(
			cwd: "",
			expectedDirectory: nil
		)
	}
}

/// Implements only unadapted protocol requirements so resume exercises the production default.
@MainActor
private final class ResumeService: CodexService
{
	var onEvent: ((AppServerEvent) -> Void)?
	var onDisconnect: ((String) -> Void)?
	var backendDiagnostics = BackendDiagnosticsSnapshot(
		cliVersion: nil,
		exitCode: nil,
		stderrTail: ""
	)
	let cwd: String

	init(cwd: String)
	{
		self.cwd = cwd
	}
	func executableVersion() async throws -> String
	{
		throw AppServerError.disconnected
	}
	func connect() async throws
	{
		throw AppServerError.disconnected
	}
	func disconnect()
	{
	}
	func accountStatus() async throws -> AccountStatus
	{
		throw AppServerError.disconnected
	}
	func startBrowserLogin() async throws -> URL
	{
		throw AppServerError.disconnected
	}
	func models() async throws -> [ModelOption]
	{
		throw AppServerError.disconnected
	}
	func threads(for directory: URL) async throws -> [ThreadSummary]
	{
		throw AppServerError.disconnected
	}
	func startThread(
		in directory: URL,
		model: String?
	) async throws -> ThreadDetail
	{
		throw AppServerError.disconnected
	}
	func resumeThread(id: String) async throws -> ThreadDetail
	{
		ThreadDetail(
			summary: ThreadSummary(json: ["id": id, "cwd": cwd])!,
			turns: [],
			nextTurnsCursor: nil
		)
	}
	func readThread(id: String) async throws -> ThreadDetail
	{
		throw AppServerError.disconnected
	}
	func loadEarlierTurns(
		threadId: String,
		cursor: String
	) async throws -> (
		turns: [CodexTurn],
		nextCursor: String?
	)
	{
		throw AppServerError.disconnected
	}
	func startTurn(
		threadId: String,
		text: String,
		model: String?,
		effort: String?
	) async throws
		-> CodexTurn
	{
		throw AppServerError.disconnected
	}
	func steerTurn(
		threadId: String,
		expectedTurnId: String,
		text: String
	) async throws -> String
	{
		throw AppServerError.disconnected
	}
	func interrupt(
		threadId: String,
		turnId: String
	) async throws
	{
		throw AppServerError.disconnected
	}
	func respond(
		to requestID: String,
		with response: InteractionResponse
	) throws
	{
		throw AppServerError.disconnected
	}
}
