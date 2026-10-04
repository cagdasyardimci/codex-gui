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
	let persistenceWorker: ProjectContextPersistenceWorker
	private let fileStorage: ProjectContextFileStorage

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
		let canonicalDirectory = directory.standardizedFileURL.resolvingSymlinksInPath()
		let worker = ProjectContextPersistenceWorker
			.shared(forCanonicalDirectory: canonicalDirectory)
		self.persistenceWorker = worker
		fileStorage = ProjectContextFileStorage(
			directory: canonicalDirectory,
			fileManager: fileManager,
			accessLock: worker.accessLock
		)
	}

	func load(for project: URL) throws -> ProjectContext
	{
		try fileStorage.load(for: project)
	}

	func save(
		_ context: ProjectContext,
		for project: URL
	) throws
	{
		try fileStorage.save(
			context,
			for: project
		)
	}

	func enqueueLoad(for project: URL) -> Task<ProjectContext, Error>
	{
		let capturedPath = project.standardizedFileURL.resolvingSymlinksInPath().path
		return enqueueLoad(canonicalProjectPath: capturedPath)
	}

	/// The caller already captured the accepted checkout; do not resolve it again.
	func enqueueLoad(canonicalProjectPath path: String) -> Task<ProjectContext, Error>
	{
		persistenceWorker.enqueue(
			canonicalProjectPath: path,
			isWrite: false
		)
		{
			[fileStorage] in
			try fileStorage.load(canonicalProjectPath: path)
		}
	}

	func enqueueSave(
		_ context: ProjectContext,
		for project: URL
	) -> Task<Void, Error>
	{
		let capturedPath = project.standardizedFileURL.resolvingSymlinksInPath().path
		return enqueueSave(
			context,
			canonicalProjectPath: capturedPath
		)
	}

	func enqueueSave(
		_ context: ProjectContext,
		canonicalProjectPath path: String
	) -> Task<Void, Error>
	{
		// This bucket identity remains fixed even if its former checkout becomes a symlink.
		persistenceWorker.enqueue(
			canonicalProjectPath: path,
			isWrite: true
		)
		{
			[fileStorage] in
			try fileStorage.save(
				context,
				canonicalProjectPath: path
			)
		}
	}

	func fileURL(for project: URL) -> URL
	{
		fileStorage.fileURL(for: project)
	}
}
