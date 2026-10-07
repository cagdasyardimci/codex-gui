import Foundation
import CryptoKit

struct PreparedBatch
{
	let directory: URL
	let backend: URL
	let sourceFingerprint: String
	let bundleFingerprint: String
	let identity: String
	let team: String
	let evidence: URL
}

func requireSuccess(
	_ status: Int32,
	_ context: String
) throws
{
	guard status == 0
	else
	{
		throw ToolError.invalid(context + " failed (\(status))")
	}
}

func prepareBatch(
	_ configuration: Configuration,
	at batch: URL
) throws -> PreparedBatch
{
	let manager = FileManager.default
	try requireSuccess(
		command(["xcodebuild", "-checkFirstLaunchStatus"]).0,
		"Xcode first-launch check"
	)
	let builtEvidence = try evidenceExecutable(
		configuration,
		log: batch.appendingPathComponent("tools-build.log")
	)
	let evidence = batch.appendingPathComponent("E2EEvidence")
	try manager.copyItem(
		at: builtEvidence,
		to: evidence
	)
	try manager.copyItem(
		at: URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL,
		to: batch.appendingPathComponent("E2EWorkflow")
	)
	let fingerprint = try sourceDigest(configuration.root)
	try fingerprint.write(
		to: batch.appendingPathComponent("source-fingerprint"),
		atomically: true,
		encoding: .utf8
	)
	try requireSuccess(
		boundedCommand(
			["./scripts/bundle.sh"],
			seconds: 900,
			log: batch.appendingPathComponent("build.log")
		),
		"Application build"
	)
	let bundle = batch.appendingPathComponent("Fixed CodexGUI.app")
	try requireSuccess(
		command(["ditto",
					configuration.root.appendingPathComponent(".build/CodexGUI.app").path,
					bundle.path]).0,
		"Application snapshot"
	)
	let fixedBackend = batch.appendingPathComponent("fixed-backend")
	if let backend = configuration.backend
	{
		try manager.createDirectory(
			at: fixedBackend,
			withIntermediateDirectories: false
		)
		try manager.copyItem(
			at: backend,
			to: fixedBackend.appendingPathComponent("qa-backend")
		)
	}
	else
	{
		try manager.copyItem(
			at: configuration.root.appendingPathComponent("Tests/E2E/MockBackend"),
			to: fixedBackend
		)
	}
	let signing = batch.appendingPathComponent("signing.txt")
	try requireSuccess(
		boundedCommand(
			["codesign", "--display", "--verbose=4", bundle.path],
			seconds: 30,
			log: signing
		),
		"Signing inspection"
	)
	let lines = try String(
		contentsOf: signing,
		encoding: .utf8
	).split(separator: "\n")
	let team = lines.first
	{
		$0.hasPrefix("TeamIdentifier=")
	}
	.map
	{
		String($0.dropFirst("TeamIdentifier=".count))
	} ?? ""
	guard !team.isEmpty, team != "not set"
	else
	{
		throw ToolError.invalid("QA app requires a development-team signature")
	}
	try requireSuccess(
		command(["codesign",
					"--display",
					"--extract-certificates=" + batch.appendingPathComponent("certificate-").path,
					bundle.path]).0,
		"Signing certificate extraction"
	)
	let certificate = try Data(contentsOf: batch.appendingPathComponent("certificate-0"))
	let identity = Insecure.SHA1.hash(data: certificate)
		.map
		{
			String(
				format: "%02X",
				$0
			)
		}.joined()
	try team.write(
		to: batch.appendingPathComponent("signing-team"),
		atomically: true,
		encoding: .utf8
	)
	try identity.write(
		to: batch.appendingPathComponent("signing-identity"),
		atomically: true,
		encoding: .utf8
	)
	return PreparedBatch(
		directory: batch,
		backend: fixedBackend,
		sourceFingerprint: fingerprint,
		bundleFingerprint: try bundleDigest(bundle),
		identity: identity,
		team: team,
		evidence: evidence
	)
}

func prepareRun(
	_ configuration: Configuration,
	batch: PreparedBatch,
	run: URL
) throws
{
	let manager = FileManager.default
	try manager.createDirectory(
		at: run,
		withIntermediateDirectories: false
	)
	let bundle = run.appendingPathComponent("CodexGUI QA.app")
	try requireSuccess(
		command(["ditto", batch.directory.appendingPathComponent(
			"Fixed CodexGUI.app"
		).path, bundle.path]).0,
		"Run application snapshot"
	)
	try requireSuccess(
		command(["codesign", "--verify", "--deep", "--strict", bundle.path]).0,
		"Run signature verification"
	)
	for entry in try manager.contentsOfDirectory(
		at: batch.backend,
		includingPropertiesForKeys: nil
	)
	{
		try manager.copyItem(
			at: entry,
			to: run.appendingPathComponent(entry.lastPathComponent)
		)
	}
	let project = run.appendingPathComponent("project with spaces")
	try manager.createDirectory(
		at: project,
		withIntermediateDirectories: false
	)
	try "print(\"Synthetic E2E fixture\")\n".write(
		to: project.appendingPathComponent("example.swift"),
		atomically: true,
		encoding: .utf8
	)
	try command(["git", "-C", project.path, "init", "-q", "--initial-branch=main"])
	try command(["git", "-C", project.path, "add", "--", "example.swift"])
	try command(["git",
					"-C",
					project.path,
					"-c",
					"user.name=Codex GUI E2E",
					"-c",
					"user.email=e2e@example.invalid",
					"-c",
					"commit.gpgSign=false",
					"-c",
					"core.hooksPath=/dev/null",
					"commit",
					"-qm",
					"test: establish E2E baseline"])
	guard let info = try PropertyListSerialization.propertyList(
		from: Data(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")),
		format: nil
	) as? [String: Any]
	else
	{
		throw ToolError.invalid("Invalid bundle property list")
	}
	try json(
		["scenario": configuration.scenario],
		to: run.appendingPathComponent("backend-state.json")
	)
	let fingerprint = try digest(
		run,
		paths: filePaths(
			batch.backend,
			ignoringPythonCaches: true
		)
	)
	try json(
		[
			"schemaVersion": 2,
			"sourceRevision": try command([
				"git",
				"-C",
				configuration.root.path,
				"rev-parse",
				"HEAD"
			])
			.1.trimmingCharacters(in: .whitespacesAndNewlines),
			"workingTreeStatus": try command(["git",
												"-C",
												configuration.root.path,
												"status",
												"--short"]).1,
			"sourceFingerprint": batch.sourceFingerprint,
			"bundleFingerprint": try bundleDigest(bundle),
			"evidenceKind": "launched app with supplied QA backend",
			"modelCalls": NSNull(),
			"runDirectory": run.path,
			"backendFingerprint": fingerprint,
			"bundleIdentifier": info["CFBundleIdentifier"] ?? NSNull(),
			"preferencesSuite": preferencesSuite(run),
		],
		to: run.appendingPathComponent("fixture.json")
	)
}

func preferencesSuite(_ run: URL) -> String
{
	let batch = run.deletingLastPathComponent().lastPathComponent
	return "local.codexgui.e2e.\(batch).\(run.lastPathComponent)"
}
