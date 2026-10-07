import Foundation
import Darwin

func runWorkflow(_ configuration: Configuration) throws -> Int32
{
	let manager = FileManager.default
	let directory = configuration.root.appendingPathComponent(".build/e2e")
	try manager.createDirectory(
		at: directory,
		withIntermediateDirectories: true
	)
	let lock = try acquireWorkflowLock(directory.appendingPathComponent("workflow.lock"))
	defer
	{
		close(lock)
	}
	let formatter = DateFormatter()
	formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
	formatter.timeZone = TimeZone(secondsFromGMT: 0)
	formatter.locale = Locale(identifier: "en_US_POSIX")
	let name = formatter.string(from: Date()) + "-" + UUID().uuidString.prefix(8).lowercased()
	let batchURL = directory.appendingPathComponent(name)
	try manager.createDirectory(
		at: batchURL,
		withIntermediateDirectories: false
	)
	output("Evidence directory: " + batchURL.path)
	defer
	{
		try? cleanup(batchURL)
	}
	do
	{
		let batch = try prepareBatch(
			configuration,
			at: batchURL
		)
		let runner = batchURL.appendingPathComponent(
			"DerivedData/Build/Products/Debug/CodexGUIE2E-Runner.app"
		)
		var runnerFingerprint = ""
		for index in 1 ... configuration.repetitions
		{
			guard interrupted == 0
			else
			{
				throw ToolError.invalid("Workflow interrupted")
			}
			guard try sourceDigest(configuration.root) == batch.sourceFingerprint
			else
			{
				throw ToolError.invalid("Source changed during batch")
			}
			if !runnerFingerprint.isEmpty,
				try bundleDigest(runner) != runnerFingerprint
			{
				throw ToolError.invalid("UI runner changed between repetitions")
			}
			let run = batchURL.appendingPathComponent(String(
				format: "run-%03d",
				index
			))
			try prepareRun(
				configuration,
				batch: batch,
				run: run
			)
			try executeRun(
				configuration,
				batch: batch,
				run: run,
				index: index
			)
			try exportResults(run)
			var accepted = try assess(
				run,
				evidence: batch.evidence
			)
			let errors = run.appendingPathComponent("identity-errors.txt")
			if try sourceDigest(configuration.root) != batch.sourceFingerprint
			{
				try append(
					"Source changed during this run; repeatability is invalid\n",
					to: errors
				)
				accepted = 1
			}
			if manager.fileExists(atPath: runner.path)
			{
				let current = try bundleDigest(runner)
				if !runnerFingerprint.isEmpty, current != runnerFingerprint
				{
					try append(
						"UI runner changed during this run\n",
						to: errors
					)
					accepted = 1
				}
				runnerFingerprint = current
			}
			if manager.fileExists(atPath: errors.path)
			{
				_ = try assess(
					run,
					evidence: batch.evidence
				)
			}
			try command([
				batch.evidence.path,
				"batch",
				batchURL.path,
				batch.sourceFingerprint,
				String(configuration.repetitions),
				runnerFingerprint,
				batch.bundleFingerprint,
			])
			guard accepted == 0
			else
			{
				throw ToolError.invalid("Run evidence was not accepted")
			}
		}
		output("Batch summary: " + batchURL.appendingPathComponent("batch-summary.json").path)
		return 0
	}
	catch
	{
		try? (String(describing: error) + "\nInspect retained logs and assessments.\n").write(
			to: batchURL.appendingPathComponent("runner-error.txt"),
			atomically: true,
			encoding: .utf8
		)
		throw error
	}
}

func executeRun(
	_ configuration: Configuration,
	batch: PreparedBatch,
	run: URL,
	index: Int
) throws
{
	var environment = ProcessInfo.processInfo.environment
	environment["DEVELOPER_DIR"] = configuration.developerDirectory
	environment["TEST_RUNNER_CODEX_GUI_E2E_RUN_DIRECTORY"] = run.path
	environment["TEST_RUNNER_CODEX_GUI_E2E_COMPACT"] = configuration.compact ? "1" : "0"
	environment["TEST_RUNNER_CODEX_GUI_E2E_PREFERENCES_SUITE"] = preferencesSuite(run)
	defer
	{
		try? cleanup(batch.directory)
	}
	let status = try boundedCommand(
		["xcodebuild",
			index == 1 ? "test" : "test-without-building",
			"-project",
			configuration.root.appendingPathComponent("Tests/E2E/CodexGUIE2E.xcodeproj").path,
			"-scheme",
			"CodexGUIE2E",
			"-destination",
			"platform=macOS",
			"-parallel-testing-enabled",
			"NO",
			"-derivedDataPath",
			batch.directory.appendingPathComponent("DerivedData").path,
			"-resultBundlePath",
			run.appendingPathComponent("workflow.xcresult").path,
			"CODE_SIGN_IDENTITY=" + batch.identity,
			"DEVELOPMENT_TEAM=" + batch.team],
		seconds: configuration.timeout,
		log: run.appendingPathComponent("xcodebuild.log"),
		environment: environment
	)
	try String(status).write(
		to: run.appendingPathComponent("exit-code"),
		atomically: true,
		encoding: .utf8
	)
}

func reassess(_ configuration: Configuration) throws -> Int32
{
	guard let run = configuration.run,
			FileManager.default.fileExists(atPath: run.path)
	else
	{
		throw ToolError.invalid("--run must name an existing run directory")
	}
	try exportResults(run)
	return try assess(
		run,
		evidence: evidenceExecutable(
			configuration,
			log: run.appendingPathComponent("tools-build.log")
		)
	)
}
