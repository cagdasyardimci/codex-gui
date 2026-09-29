import Darwin
import Foundation

/// Separate atomic records avoid replacing another task's ownership during a crash.
final class TaskWorkspaceStore
{
	private struct Document: Codable
	{
		let version: Int
		let workspace: TaskWorkspace
	}

	private let directory: URL
	private let fileManager: FileManager

	init(
		directory: URL = TaskWorkspaceLocations().records,
		fileManager: FileManager = .default
	)
	{
		self.directory = directory
		self.fileManager = fileManager
	}

	/// An OS lock serializes task ownership across windows and app processes.
	/// It is released by the OS if the process exits during a Git operation.
	func withExclusiveLock<Value>(_ operation: () throws -> Value) throws -> Value
	{
		try fileManager.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
		let lockPath = directory.appendingPathComponent(".lock").path
		let descriptor = lockPath.withCString
		{
			Darwin.open(
				$0,
				O_CREAT | O_RDWR | O_EXLOCK | O_CLOEXEC | O_NOFOLLOW,
				0o600
			)
		}
		guard descriptor >= 0
		else
		{
			throw TaskWorkspaceError.storageFailure(String(cString: Darwin.strerror(errno)))
		}
		defer
		{
			Darwin.close(descriptor)
		}
		return try operation()
	}

	func loadAll() throws -> [TaskWorkspace]
	{
		guard fileManager.fileExists(atPath: directory.path)
		else
		{
			return []
		}
		let directoryContents = try fileManager.contentsOfDirectory(
			at: directory,
			includingPropertiesForKeys: nil
		)
		let recordFiles = directoryContents.filter
		{
			$0.pathExtension == "json"
		}
		let workspaces = try recordFiles.map
		{
			try loadFile(at: $0)
		}

		return workspaces.sorted
		{
			$0.createdAt < $1.createdAt
		}
	}

	func load(id: UUID) throws -> TaskWorkspace?
	{
		let file = fileURL(for: id)
		guard fileManager.fileExists(atPath: file.path)
		else
		{
			return nil
		}
		return try loadFile(at: file)
	}

	func save(_ workspace: TaskWorkspace) throws
	{
		try validateOwnershipBeforeSaving(workspace)

		try fileManager.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)

		let document = Document(
			version: 1,
			workspace: workspace
		)

		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		let data = try encoder.encode(document)

		try data.write(
			to: fileURL(for: workspace.id),
			options: .atomic
		)
	}

	private func validateOwnershipBeforeSaving(_ workspace: TaskWorkspace) throws
	{
		if let previous = try load(id: workspace.id)
		{
			guard previous.hasSameOwnership(as: workspace),
					previous.threadID == nil || previous.threadID == workspace.threadID
			else
			{
				throw TaskWorkspaceError.ownershipConflict("record \(workspace.id) changed owner")
			}
		}
	}

	private func loadFile(at file: URL) throws -> TaskWorkspace
	{
		let document = try readDocument(at: file)
		try validateDocument(
			document,
			at: file
		)
		return document.workspace
	}

	private func readDocument(at file: URL) throws -> Document
	{
		let document: Document
		do
		{
			let data = try Data(contentsOf: file)
			document = try JSONDecoder().decode(
				Document.self,
				from: data
			)
		}
		catch
		{
			throw TaskWorkspaceError.invalidRecord("\(file.path): \(error.localizedDescription)")
		}
		return document
	}

	private func validateDocument(
		_ document: Document,
		at file: URL
	) throws
	{
		guard document.version == 1
		else
		{
			throw TaskWorkspaceError.unsupportedRecordVersion(document.version)
		}
		guard file.lastPathComponent == "\(document.workspace.id.uuidString.lowercased()).json"
		else
		{
			throw TaskWorkspaceError.invalidRecord("file name does not match its workspace ID")
		}
	}

	private func fileURL(for id: UUID) -> URL
	{
		directory.appendingPathComponent("\(id.uuidString.lowercased()).json")
	}
}
