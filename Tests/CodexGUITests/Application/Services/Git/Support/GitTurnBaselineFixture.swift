import Foundation
import Testing

@testable import CodexGUI

struct GitTurnBaselineFixture: Sendable
{
	let container: URL
	let root: URL
	let storageRoot: URL
	let sessionID = UUID()
	let requestID = UUID()

	init(commitInitial: Bool = true) throws
	{
		container = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		root = container.appendingPathComponent("repository")
		storageRoot = container.appendingPathComponent("baselines")
		try FileManager.default.createDirectory(
			at: root,
			withIntermediateDirectories: true
		)
		try git(["init", "-q"])
		try write(
			"source.txt",
			"original\ncontext\n"
		)
		try git(["add", "--", "source.txt"])
		if commitInitial
		{
			try commit()
		}
	}

	func remove()
	{
		let enumerator = FileManager.default.enumerator(
			at: container,
			includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
		)
		while let url = enumerator?.nextObject() as? URL
		{
			let resourceValues = try? url.resourceValues(forKeys: [
				.isDirectoryKey,
				.isSymbolicLinkKey
			])
			let isRegularDirectory =
				resourceValues?.isDirectory == true && resourceValues?.isSymbolicLink != true
			if isRegularDirectory
			{
				try? FileManager.default.setAttributes(
					[.posixPermissions: 0o700],
					ofItemAtPath: url.path
				)
			}
		}
		try? FileManager.default.removeItem(at: container)
	}

	func write(
		_ path: String,
		_ content: String
	) throws
	{
		let destination = root.appendingPathComponent(path)
		try FileManager.default.createDirectory(
			at: destination.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		try Data(content.utf8).write(to: destination)
	}

	func commit() throws
	{
		try git([
			"-c",
			"user.name=Test",
			"-c",
			"user.email=test@example.invalid",
			"commit",
			"-qm",
			"Fixture"
		])
	}

	func captureRequest(threadID: String = "fixture-chat") -> GitTurnBaselineCaptureRequest
	{
		GitTurnBaselineCaptureRequest(
			context: OperationContext(
				workspace: WorkspaceIdentity(
					sessionID: sessionID,
					canonicalCheckoutPath: root.path
				),
				generation: 1,
				requestID: requestID,
				threadID: threadID
			),
			threadID: threadID,
			repositoryRoot: root.path
		)
	}

	func capture(
		_ service: LocalGitTurnBaselineService,
		threadID: String = "fixture-chat"
	) async throws -> GitTurnBaselineReference
	{
		let result = await service.capture(captureRequest(threadID: threadID))
		guard case .captured(let reference) = result
		else
		{
			Issue.record("Capture failed: \(result)")
			throw FixtureError.unavailable
		}
		return reference
	}

	func bind(
		_ reference: GitTurnBaselineReference,
		service: LocalGitTurnBaselineService,
		turnID: String
	) async throws -> GitTurnBaselineReference
	{
		guard case .captured(let bound) = await service.bind(
			reference,
			turnID: turnID
		)
		else
		{
			throw FixtureError.unavailable
		}
		return bound
	}

	func comparison(
		_ service: LocalGitTurnBaselineService,
		baseline: GitTurnBaselineReference
	) async throws -> GitComparisonSnapshot
	{
		let result = await service.compare(comparisonRequest(
			baseline: baseline,
			turnID: baseline.acceptedTurnID
		))
		guard case .snapshot(let snapshot) = result
		else
		{
			Issue.record("Comparison failed: \(result)")
			throw FixtureError.unavailable
		}
		return snapshot
	}

	func comparisonRequest(
		baseline: GitTurnBaselineReference?,
		turnID: String?,
		sessionID: UUID? = nil,
		threadID: String = "fixture-chat"
	) -> GitComparisonRequest
	{
		let session = sessionID ?? self.sessionID
		var snapshot = ConversationSnapshot(
			projectPath: root.path,
			threads: [],
			selectedThreadID: threadID,
			entries: [],
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "",
			canSend: false,
			accountDescription: "",
			backendDescription: "",
			executionState: .ready,
			statusMessage: nil,
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: [],
			recentProjects: []
		)
		snapshot.workspaceOwner = WorkspaceLifecycleOwnerReference(
			owner: .source(sessionID: session),
			workspace: WorkspaceIdentity(
				sessionID: session,
				canonicalCheckoutPath: root.path
			)
		)
		return GitComparisonRequest(
			owner: FeaturePresentationOwner(snapshot),
			repositoryRoot: root.path,
			scope: .lastTurn,
			generation: 1,
			lastTurnBaseline: baseline,
			lastTurnID: turnID
		)
	}

	func repositoryEvidence() throws -> Data
	{
		var bytes = try git(["status", "--porcelain=v2", "-z", "--untracked-files=all"])
		bytes.append(try Data(contentsOf: root.appendingPathComponent(".git/index")))
		bytes.append(try git(["show-ref", "--head"]))
		bytes.append(try git(["ls-files", "--stage", "-z"]))
		bytes.append(try Data(contentsOf: root.appendingPathComponent("source.txt")))
		let objects = root.appendingPathComponent(".git/objects")
		let files = try FileManager.default.subpathsOfDirectory(atPath: objects.path).sorted()
		bytes.append(Data(files.joined(separator: "\0").utf8))
		return bytes
	}

	func checkPatch(
		_ patch: Data,
		in directory: URL? = nil
	) throws
	{
		try gitWithInput(
			["apply", "--check"],
			bytes: patch,
			in: directory
		)
	}

	func gitWithInput(
		_ arguments: [String],
		bytes: Data,
		in directory: URL? = nil
	) throws
	{
		let result = try GitTestCommandRunner.run(
			in: directory ?? root,
			arguments: arguments,
			input: bytes
		)
		guard result.terminationStatus == 0
		else
		{
			throw FixtureError.command
		}
	}

	@discardableResult
	func git(_ arguments: [String]) throws -> Data
	{
		let result = try GitTestCommandRunner.run(
			in: root,
			arguments: arguments
		)
		guard result.terminationStatus == 0
		else
		{
			throw FixtureError.command
		}
		return result.output
	}

	private enum FixtureError: Error
	{
		case unavailable, command
	}
}
