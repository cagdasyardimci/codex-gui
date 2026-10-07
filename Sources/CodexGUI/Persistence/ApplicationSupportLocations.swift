import Foundation

/// Explicit opt-in storage isolation for launched-app tests and native QA.
enum ApplicationSupportLocations
{
	static func directory(_ component: String) -> URL
	{
		let configured = ProcessInfo.processInfo.environment["CODEX_GUI_SUPPORT_ROOT"]
		let root = configured.flatMap
		{
			$0.hasPrefix("/") ? URL(
				fileURLWithPath: $0,
				isDirectory: true
			) : nil
		} ?? FileManager.default.urls(
			for: .applicationSupportDirectory,
			in: .userDomainMask
		)[0].appendingPathComponent(
			"CodexGUI",
			isDirectory: true
		)
		return root.appendingPathComponent(
			component,
			isDirectory: true
		)
	}
}
