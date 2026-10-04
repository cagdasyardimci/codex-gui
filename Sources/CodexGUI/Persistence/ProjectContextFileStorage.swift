import CryptoKit
import Foundation

/// Configuration is immutable, and every FileManager call holds the directory's shared lock.
/// This SDK does not mark FileManager Sendable; it never escapes this locked backend.
struct ProjectContextFileStorage: @unchecked Sendable
{
	private struct Document: Codable
	{
		let version: Int
		let projectPath: String
		let context: ProjectContext
	}

	private let directory: URL
	private let fileManager: FileManager
	private let accessLock: NSLock

	init(
		directory: URL,
		fileManager: FileManager,
		accessLock: NSLock
	)
	{
		self.directory = directory
		self.fileManager = fileManager
		self.accessLock = accessLock
	}

	func load(for project: URL) throws -> ProjectContext
	{
		try load(canonicalProjectPath: canonicalPath(for: project))
	}

	/// A captured checkout path remains its bucket identity after that checkout moves.
	func load(canonicalProjectPath path: String) throws -> ProjectContext
	{
		accessLock.lock()
		defer
		{
			accessLock.unlock()
		}
		let documentURL = fileURL(canonicalPath: path)
		guard fileManager.fileExists(atPath: documentURL.path)
		else
		{
			return ProjectContext()
		}
		let document = try readDocument(at: documentURL)
		try validateDocument(
			document,
			canonicalPath: path
		)
		return document.context
	}

	func save(
		_ context: ProjectContext,
		for project: URL
	) throws
	{
		try save(
			context,
			canonicalProjectPath: canonicalPath(for: project)
		)
	}

	func save(
		_ context: ProjectContext,
		canonicalProjectPath path: String
	) throws
	{
		accessLock.lock()
		defer
		{
			accessLock.unlock()
		}
		let documentURL = fileURL(canonicalPath: path)
		// Revalidate the file when the ordered write starts, including external modifications.
		if fileManager.fileExists(atPath: documentURL.path)
		{
			let existingDocument = try readDocument(at: documentURL)
			try validateDocument(
				existingDocument,
				canonicalPath: path
			)
		}

		try fileManager.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
		let document = Document(
			version: 1,
			projectPath: path,
			context: context
		)
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		let data = try encoder.encode(document)

		try data.write(
			to: documentURL,
			options: .atomic
		)
	}

	func fileURL(for project: URL) -> URL
	{
		fileURL(canonicalPath: canonicalPath(for: project))
	}

	private func fileURL(canonicalPath path: String) -> URL
	{
		let digest = SHA256.hash(data: Data(path.utf8))
		let filename = digest.map
		{
			String(
				format: "%02x",
				$0
			)
		}.joined() + ".json"
		return directory.appendingPathComponent(filename)
	}

	private func canonicalPath(for project: URL) -> String
	{
		project.standardizedFileURL.resolvingSymlinksInPath().path
	}

	private func readDocument(at documentURL: URL) throws -> Document
	{
		do
		{
			let data = try Data(contentsOf: documentURL)
			return try JSONDecoder().decode(
				Document.self,
				from: data
			)
		}
		catch
		{
			throw ProjectContextStoreError.unreadable(
				documentURL,
				error
			)
		}
	}

	private func validateDocument(
		_ document: Document,
		canonicalPath path: String
	) throws
	{
		guard document.version == 1
		else
		{
			throw ProjectContextStoreError.unsupportedVersion(document.version)
		}
		guard document.projectPath == path
		else
		{
			throw ProjectContextStoreError.wrongProject
		}
	}
}
