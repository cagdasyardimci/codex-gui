import CryptoKit
import Foundation

enum ProjectContextStoreError: LocalizedError
{
	case unsupportedVersion(Int)
	case wrongProject
	case unreadable(
		URL,
		Error
	)

	var errorDescription: String?
	{
		switch self
		{
		case .unsupportedVersion(let version):
			"Project context uses unsupported version \(version). Its file was left unchanged."
		case .wrongProject:
			"Project context belongs to another project. Its file was left unchanged."
		case .unreadable(
			let url,
			let cause
		):
			"Could not read project context at \(url.path): \(cause.localizedDescription). Its "
				+ "file was left unchanged."
		}
	}
}

@MainActor
final class ProjectContextStore
{
	private struct Document: Codable
	{
		let version: Int
		let projectPath: String
		let context: ProjectContext
	}

	private let directory: URL
	private let fileManager: FileManager

	init(
		directory: URL = FileManager.default.urls(
			for: .applicationSupportDirectory,
			in: .userDomainMask
		)[0].appendingPathComponent(
			"CodexGUI/project-context",
			isDirectory: true
		),
		fileManager: FileManager = .default
	)
	{
		self.directory = directory
		self.fileManager = fileManager
	}

	func load(for project: URL) throws -> ProjectContext
	{
		let fileURL = fileURL(for: project)
		guard fileManager.fileExists(atPath: fileURL.path)
		else
		{
			return ProjectContext()
		}

		let document = try readDocument(at: fileURL)
		try validateDocument(
			document,
			for: project
		)

		return document.context
	}

	private func readDocument(at fileURL: URL) throws -> Document
	{
		let data: Data
		do
		{
			data = try Data(contentsOf: fileURL)
		}
		catch
		{
			throw ProjectContextStoreError.unreadable(
				fileURL,
				error
			)
		}

		let document: Document
		do
		{
			document = try JSONDecoder().decode(
				Document.self,
				from: data
			)
		}
		catch
		{
			throw ProjectContextStoreError.unreadable(
				fileURL,
				error
			)
		}

		return document
	}

	private func validateDocument(
		_ document: Document,
		for project: URL
	) throws
	{
		guard document.version == 1
		else
		{
			throw ProjectContextStoreError.unsupportedVersion(document.version)
		}
		guard document.projectPath == canonicalPath(for: project)
		else
		{
			throw ProjectContextStoreError.wrongProject
		}
	}

	func save(
		_ context: ProjectContext,
		for project: URL
	) throws
	{
		let fileURL = fileURL(for: project)
		// Refuse to replace data that this version cannot read.
		if fileManager.fileExists(atPath: fileURL.path)
		{
			_ = try load(for: project)
		}

		try fileManager.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)

		let document = Document(
			version: 1,
			projectPath: canonicalPath(for: project),
			context: context
		)

		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		let data = try encoder.encode(document)

		try data.write(
			to: fileURL,
			options: .atomic
		)
	}

	func fileURL(for project: URL) -> URL
	{
		let path = canonicalPath(for: project)
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
}
