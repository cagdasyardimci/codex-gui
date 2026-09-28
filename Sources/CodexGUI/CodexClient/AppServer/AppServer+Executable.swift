import Foundation

// Locates the CLI and validates its supported protocol version.
extension AppServer
{
	static func executableURL() -> URL?
	{
		let environment = ProcessInfo.processInfo.environment
		let nodeVersions = FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent(".nvm/versions/node")
		let installedNodeVersions = try? FileManager.default.contentsOfDirectory(
			at: nodeVersions,
			includingPropertiesForKeys: nil
		)
		let nvmExecutables = installedNodeVersions?.map
		{
			$0.appendingPathComponent("bin/codex").path
		} ?? []
		let preferredExecutables: [String?] = [
			environment["CODEX_EXECUTABLE"],
			"/opt/homebrew/bin/codex",
			"/usr/local/bin/codex",
		]
		let candidateExecutables = preferredExecutables + nvmExecutables.map(Optional.some)
		let candidates = candidateExecutables.compactMap
		{
			$0
		}

		for path in candidates where FileManager.default.isExecutableFile(atPath: path)
		{
			return URL(fileURLWithPath: path)
		}

		for directory in (environment["PATH"] ?? "").split(separator: ":")
		{
			let path = String(directory) + "/codex"
			if FileManager.default.isExecutableFile(atPath: path)
			{
				return URL(fileURLWithPath: path)
			}
		}
		return nil
	}

	func executableVersion() async throws -> String
	{
		guard let executable = executableOverride ?? Self.executableURL()
		else
		{
			throw AppServerError.executableMissing
		}
		let timeout = versionCheckTimeout
		return try await Task.detached(priority: .utility)
		{
			try ExecutableVersionProbe.readVersion(
				from: executable,
				timeout: timeout
			)
		}.value
	}

	func validateProtocolVersion(_ version: String) throws
	{
		let versionNumber = version.split(separator: " ").last.map(String.init) ?? ""
		let versionComponents = versionNumber.split(separator: ".").compactMap
		{
			Int($0)
		}
		let minimumSupportedVersion = [0, 153, 2]
		let meetsMinimumVersion = !Array(versionComponents.prefix(3))
			.lexicographicallyPrecedes(minimumSupportedVersion)
		guard versionComponents.count >= 3, meetsMinimumVersion
		else
		{
			throw AppServerError.incompatibleVersion(version)
		}
	}
}
