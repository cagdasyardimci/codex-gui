import Foundation

enum AppServerTestExecutable
{
	static func temporaryDirectory() async throws -> URL
	{
		try await BackgroundTestWork.perform
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
	}

	static func mockExecutable(
		in directory: URL,
		script: String
	) async throws -> URL
	{
		try await BackgroundTestWork.perform
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
}
