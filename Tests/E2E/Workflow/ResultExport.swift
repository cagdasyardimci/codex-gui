import Foundation

func exportResults(_ run: URL) throws
{
	let manager = FileManager.default
	let errors = run.appendingPathComponent("export-errors.txt")
	try "".write(
		to: errors,
		atomically: true,
		encoding: .utf8
	)
	let result = run.appendingPathComponent("workflow.xcresult")
	guard manager.fileExists(atPath: result.path)
	else
	{
		try append(
			"No xcresult bundle was produced; inspect xcodebuild.log.\n",
			to: errors
		)
		return
	}
	for kind in ["summary", "tests"]
	{
		let temporary = run.appendingPathComponent(kind + ".json.tmp")
		let status = try boundedCommand(
			["xcrun", "xcresulttool", "get", "test-results", kind, "--path", result.path],
			seconds: 120,
			log: run.appendingPathComponent(kind + "-export.log"),
			stdout: temporary
		)
		if status == 0
		{
			let destination = run.appendingPathComponent(kind + ".json")
			if manager.fileExists(atPath: destination.path)
			{
				try manager.removeItem(at: destination)
			}
			try manager.moveItem(
				at: temporary,
				to: destination
			)
		}
		else
		{
			try append(
				"Failed to export " + kind + "\n",
				to: errors
			)
			try? manager.removeItem(at: temporary)
		}
	}
	let staging = run.appendingPathComponent(".attachments-export-" + UUID().uuidString)
	let status = try boundedCommand(
		["xcrun",
			"xcresulttool",
			"export",
			"attachments",
			"--path",
			result.path,
			"--output-path",
			staging.path],
		seconds: 120,
		log: run.appendingPathComponent("attachment-export.log")
	)
	if status == 0
	{
		try replaceAttachments(
			staging,
			in: run
		)
	}
	else
	{
		try append(
			"Failed to export attachments\n",
			to: errors
		)
	}
}

// Keep the previous complete export until its replacement is ready.
func replaceAttachments(
	_ staging: URL,
	in run: URL
) throws
{
	let manager = FileManager.default
	let destination = run.appendingPathComponent("attachments")
	let backup = run.appendingPathComponent(".attachments-previous-" + UUID().uuidString)
	let hadPrevious = manager.fileExists(atPath: destination.path)
	if hadPrevious
	{
		try manager.moveItem(
			at: destination,
			to: backup
		)
	}
	do
	{
		try manager.moveItem(
			at: staging,
			to: destination
		)
	}
	catch
	{
		if hadPrevious
		{
			try manager.moveItem(
				at: backup,
				to: destination
			)
		}
		throw error
	}
	if hadPrevious
	{
		try manager.removeItem(at: backup)
	}
}

func append(
	_ value: String,
	to url: URL
) throws
{
	if !FileManager.default.fileExists(atPath: url.path)
	{
		_ = FileManager.default.createFile(
			atPath: url.path,
			contents: nil
		)
	}
	let handle = try FileHandle(forWritingTo: url)
	defer
	{
		try? handle.close()
	}
	try handle.seekToEnd()
	try handle.write(contentsOf: Data(value.utf8))
}

func assess(
	_ run: URL,
	evidence: URL
) throws -> Int32
{
	let status = (try? String(
		contentsOf: run.appendingPathComponent("exit-code"),
		encoding: .utf8
	)) ?? "1"
	let result = try command(
		[evidence.path,
			"report",
			run.path,
			status.trimmingCharacters(in: .whitespacesAndNewlines)],
		allowFailure: true
	)
	output(result.1.trimmingCharacters(in: .whitespacesAndNewlines))
	return result.0

}

func evidenceExecutable(
	_ configuration: Configuration,
	log: URL
) throws -> URL
{
	let package = configuration.root.appendingPathComponent("Tests/E2E").path
	// Ask SwiftPM to refresh the validator; an existing binary can be stale.
	try requireSuccess(
		boundedCommand(
			["xcrun", "swift", "build", "--package-path", package, "--product", "E2EEvidence"],
			seconds: 900,
			log: log
		),
		"Evidence tool build"
	)
	let bin = try command(["xcrun", "swift", "build", "--package-path", package, "--show-bin-path"])
		.1.trimmingCharacters(in: .whitespacesAndNewlines)
	return URL(fileURLWithPath: bin).appendingPathComponent("E2EEvidence")
}
