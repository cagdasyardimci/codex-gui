import Foundation

enum AppServerTestExecutable
{
	static func temporaryDirectory() throws -> URL
	{
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(
				"CodexGUIIntegrationTests-\(UUID().uuidString)",
				isDirectory: true
			)
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
		return directory
	}

	static func mockExecutable(
		in directory: URL,
		script: String
	) throws -> URL
	{
		let executable = directory.appendingPathComponent("mock-codex")
		try script.write(
			to: executable,
			atomically: true,
			encoding: .utf8
		)
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o755],
			ofItemAtPath: executable.path
		)
		return executable
	}
}
