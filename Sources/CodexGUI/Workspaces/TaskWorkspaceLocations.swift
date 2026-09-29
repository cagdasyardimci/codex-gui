import Foundation

/// A QA launch can keep its workspace records and checkouts outside normal app data.
struct TaskWorkspaceLocations
{
	let root: URL

	init(environment: [String: String] = ProcessInfo.processInfo.environment)
	{
		if let configured = environment["CODEX_GUI_WORKSPACE_ROOT"], !configured.isEmpty
		{
			root = URL(
				fileURLWithPath: configured,
				isDirectory: true
			).standardizedFileURL.resolvingSymlinksInPath()
		}
		else
		{
			let applicationSupportDirectory = FileManager.default.urls(
				for: .applicationSupportDirectory,
				in: .userDomainMask
			)[0]
			root = applicationSupportDirectory.appendingPathComponent(
				"CodexGUI/task-workspaces",
				isDirectory: true
			)
		}
	}

	var records: URL
	{
		root.appendingPathComponent(
			"records",
			isDirectory: true
		)
	}

	var checkouts: URL
	{
		root.appendingPathComponent(
			"checkouts",
			isDirectory: true
		)
	}
}
