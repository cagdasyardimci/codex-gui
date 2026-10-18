import AppKit
import Foundation

enum EditorOpeningError: LocalizedError
{
	case invalidProject(URL)
	case outsideProject(String)
	case missingFile(String)

	var errorDescription: String?
	{
		switch self
		{
		case .invalidProject(let project):
			return "The project folder is unavailable: \(project.path)"
		case .outsideProject(let path):
			return "The file is outside the project folder: \(path)"
		case .missingFile(let path):
			return "The changed file no longer exists: \(path)"
		}
	}
}

@MainActor
final class EditorOpeningService
{
	private static let applicationDefaultsKey = "preferredEditorApplication"
	private let defaults: UserDefaults

	init(defaults: UserDefaults = .standard)
	{
		self.defaults = defaults
	}

	var preferredApplication: URL?
	{
		get
		{
			defaults.string(forKey: Self.applicationDefaultsKey).map
			{
				URL(fileURLWithPath: $0)
			}
		}
		set
		{
			defaults.set(
				newValue?.path,
				forKey: Self.applicationDefaultsKey
			)
		}
	}

	func open(
		path: String,
		project: URL,
		line: Int
	) async throws -> String?
	{
		let file = try Self.resolve(
			path: path,
			project: project
		)
		let line = max(
			1,
			line
		)

		guard let application = preferredApplication
		else
		{
			let opened = NSWorkspace.shared.open(file)
			guard opened
			else
			{
				return "Could not open the file with the system default application."
			}

			if line > 1
			{
				return "Opened with the system default application; line navigation is unavailable."
			}

			return nil
		}

		guard FileManager.default.fileExists(atPath: application.path)
		else
		{
			let opened = NSWorkspace.shared.open(file)
			return opened
				? "The selected editor is unavailable; opened the file with the system default "
				+ "application."
				: "The selected editor is unavailable, and the system default application could "
				+ "not open the file."
		}

		let bundleID = Bundle(url: application)?.bundleIdentifier
		let supportsLineNavigation =
			bundleID == "com.microsoft.VSCode" || bundleID == "com.microsoft.VSCodeInsiders"

		if supportsLineNavigation
		{
			if await Self.openInVSCode(
				application: application,
				file: file,
				line: line
			)
			{
				return nil
			}
			let opened = NSWorkspace.shared.open(file)
			return opened
				? "Could not start the selected editor; opened the file with the system default "
				+ "application."
				: "Could not start the selected editor or open the file with the system default "
				+ "application."
		}

		do
		{
			try await Self.openInApplication(
				application,
				file: file
			)
			return line > 1 ? "Opened in the selected editor; line navigation is unavailable." : nil
		}
		catch
		{
			let opened = NSWorkspace.shared.open(file)
			return opened
				? "The selected editor could not open the file; opened it with the system default "
				+ "application."
				: "The selected editor and the system default application could not open the file."
		}
	}

	/// Opens once with the chosen application without changing the saved preference.
	func open(
		path: String,
		project: URL,
		withApplicationAt application: URL
	) async throws
	{
		let file = try Self.resolve(
			path: path,
			project: project
		)
		try await Self.openInApplication(
			application,
			file: file
		)
	}

	func openWithDefault(
		path: String,
		project: URL
	) throws
	{
		let file = try Self.resolve(
			path: path,
			project: project
		)
		guard NSWorkspace.shared.open(file)
		else
		{
			throw NSError(
				domain: "FileOpening",
				code: 1,
				userInfo: [
					NSLocalizedDescriptionKey: "The default application could not open this file."
				]
			)
		}
	}

	func openFolder(
		path: String,
		project: URL,
		withApplicationAt application: URL
	) async throws
	{
		let file = try Self.resolve(
			path: path,
			project: project
		)
		try await Self.openInApplication(
			application,
			file: file.deletingLastPathComponent()
		)
	}

	private static func resolve(
		path: String,
		project: URL
	) throws -> URL
	{
		let manager = FileManager.default
		let root = project.standardizedFileURL.resolvingSymlinksInPath()
		var isDirectory: ObjCBool = false
		guard manager.fileExists(
			atPath: root.path,
			isDirectory: &isDirectory
		),
			isDirectory.boolValue
		else
		{
			throw EditorOpeningError.invalidProject(project)
		}

		let supplied = URL(
			fileURLWithPath: path,
			relativeTo: root
		).standardizedFileURL
		let file = supplied.resolvingSymlinksInPath()
		let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
		guard file.path.hasPrefix(rootPrefix)
		else
		{
			throw EditorOpeningError.outsideProject(path)
		}
		var isFile: ObjCBool = false
		guard manager.fileExists(
			atPath: file.path,
			isDirectory: &isFile
		), !isFile.boolValue
		else
		{
			throw EditorOpeningError.missingFile(path)
		}
		return file
	}

	private static func openInVSCode(
		application: URL,
		file: URL,
		line: Int
	) async -> Bool
	{
		let executable = application.appendingPathComponent("Contents/Resources/app/bin/code")
		guard FileManager.default.isExecutableFile(atPath: executable.path)
		else
		{
			return false
		}
		let arguments = ["--goto", "\(file.path):\(max(1, line))"]
		return await Task.detached(priority: .userInitiated)
		{
			runVSCodeCLI(
				executable: executable,
				arguments: arguments
			)
		}.value
	}

	private nonisolated static func runVSCodeCLI(
		executable: URL,
		arguments: [String]
	) -> Bool
	{
		let process = Process()
		process.executableURL = executable
		process.arguments = arguments
		process.standardOutput = FileHandle.nullDevice
		process.standardError = FileHandle.nullDevice
		let finished = DispatchSemaphore(value: 0)
		process.terminationHandler =
		{
			_ in finished.signal()
		}
		do
		{
			try process.run()
			guard finished.wait(timeout: .now() + 10) == .success
			else
			{
				if process.isRunning
				{
					process.terminate()
				}
				if finished.wait(timeout: .now() + 1) != .success, process.isRunning
				{
					kill(
						process.processIdentifier,
						SIGKILL
					)
				}
				return false
			}
			return process.terminationStatus == 0
		}
		catch
		{
			return false
		}
	}

	private static func openInApplication(
		_ application: URL,
		file: URL
	) async throws
	{
		try await withCheckedThrowingContinuation
		{
			(continuation: CheckedContinuation<Void, Error>) in
			let configuration = NSWorkspace.OpenConfiguration()
			NSWorkspace.shared.open(
				[file],
				withApplicationAt: application,
				configuration: configuration
			)
			{
				_, error in
				if let error
				{
					continuation.resume(throwing: error)
				}
				else
				{
					continuation.resume()
				}
			}
		}
	}
}
