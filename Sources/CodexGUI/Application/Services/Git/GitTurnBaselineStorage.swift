import Darwin
import Foundation

struct GitTurnBaselineStorage: Sendable
{
	let root: URL
	let limits: GitTurnBaselineLimits
	private static let maximumMetadataBytes = 8 * 1024 * 1024

	func capture(
		_ request: GitTurnBaselineCaptureRequest
	) -> Result<GitTurnBaselineRecord, GitComparisonFailure>
	{
		var capturedID: UUID?
		do
		{
			try Task.checkCancellation()
			let canonicalRoot = WorkspaceFileIdentity.canonicalRootPath(
				URL(fileURLWithPath: request.repositoryRoot)
			)
			guard let checkoutPath = request.context.workspace.canonicalCheckoutPath
			else
			{
				throw GitTurnBaselineReadError.failure(.baselineOwnershipMismatch)
			}
			let capturedRoot = WorkspaceFileIdentity
				.canonicalRootPath(URL(fileURLWithPath: checkoutPath))
			guard capturedRoot == canonicalRoot,
					!request.threadID.isEmpty
			else
			{
				throw GitTurnBaselineReadError.failure(.baselineOwnershipMismatch)
			}

			try prepareStorage(outside: canonicalRoot)
			let tree = try GitTurnBaselineTreeReader(
				root: canonicalRoot,
				limits: limits
			).capture()

			let identity = GitTurnBaselineIdentity(
				id: UUID(),
				workspaceSessionID: request.context.workspace.sessionID,
				repositoryRoot: canonicalRoot,
				executionGeneration: request.context.generation,
				submissionRequestID: request.context.requestID,
				threadID: request.threadID,
				workspaceCheckoutPath: checkoutPath
			)
			capturedID = identity.id
			let reference = GitTurnBaselineReference(
				identity: identity,
				capturedAt: Date(),
				trackedFileCount: tree.files.count,
				byteCount: tree.byteCount,
				acceptedTurnID: nil
			)
			let record = GitTurnBaselineRecord(
				reference: reference,
				entries: tree.files.map(\.entry),
				indexManifest: tree.indexManifest
			)

			try persistCapturedTree(
				tree,
				record: record
			)
			return .success(record)
		}
		catch
		{
			if let capturedID
			{
				remove(capturedID)
			}
			return .failure(failure(error))
		}
	}

	private func persistCapturedTree(
		_ tree: GitTurnBaselineTree,
		record: GitTurnBaselineRecord
	) throws
	{
		let directory = location(record.reference.identity.id)
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: false,
			attributes: [.posixPermissions: 0o700]
		)
		try materialize(
			tree,
			at: directory.appendingPathComponent("before")
		)

		try Task.checkCancellation()
		guard save(record)
		else
		{
			throw unavailable("The baseline could not be saved.")
		}
	}

	func compare(
		_ record: GitTurnBaselineRecord,
		request: GitComparisonRequest
	) -> GitComparisonResult
	{
		var scratch: URL?
		do
		{
			try Task.checkCancellation()
			let oldTree = try validatedTree(record)
			let current = try GitTurnBaselineTreeReader(
				root: record.reference.identity.repositoryRoot,
				limits: limits
			).capture(additionalPaths: record.entries.map(\.path))

			let work = root.appendingPathComponent(
				"comparison-" + UUID().uuidString,
				isDirectory: true
			)
			scratch = work
			try FileManager.default.createDirectory(
				at: work,
				withIntermediateDirectories: false,
				attributes: [.posixPermissions: 0o700]
			)
			try materialize(
				oldTree,
				at: work.appendingPathComponent("before")
			)
			try materialize(
				current,
				at: work.appendingPathComponent("after")
			)
			defer
			{
				removeDirectory(work)
			}

			let arguments = [
				"diff",
				"--no-index",
				"--no-ext-diff",
				"--no-textconv",
				"--no-color",
				"--full-index",
				"--find-renames",
				"--src-prefix=a/",
				"--dst-prefix=b/",
				"--unified=2147483647",
				"--",
				"before",
				"after"
			]
			let rawPatch = try GitTurnBaselineGitCommands(
				root: work.path,
				maximumBytes: limits.maximumPatchBytes
			).run(
				arguments,
				acceptsDifference: true
			)
			let patch = GitTurnBaselinePatchNormalizer.normalize(rawPatch)
			try Task.checkCancellation()
			guard String(
				data: patch,
				encoding: .utf8
			) != nil
			else
			{
				throw GitTurnBaselineReadError.failure(.unsupportedTextEncoding)
			}
			return .snapshot(GitComparisonSnapshot(
				request: request,
				id: UUID().uuidString,
				resolvedBase: "Before turn " + (record.reference.acceptedTurnID ?? "submission"),
				resolvedTarget: "Working tree (tracked files)",
				patch: patch,
				files: GitComparisonPatchParser.files(in: patch)
			))
		}
		catch
		{
			if let scratch
			{
				removeDirectory(scratch)
			}
			return .unavailable(failure(error))
		}
	}

	func save(_ record: GitTurnBaselineRecord) -> Bool
	{
		do
		{
			let directory = location(record.reference.identity.id)
			try requireDirectory(directory)
			let bytes = try JSONEncoder().encode(record)
			guard bytes.count <= Self.maximumMetadataBytes
			else
			{
				return false
			}
			let temporary = directory.appendingPathComponent("metadata-" + UUID().uuidString)
			try bytes.write(
				to: temporary,
				options: .withoutOverwriting
			)
			try FileManager.default.setAttributes(
				[.posixPermissions: 0o400],
				ofItemAtPath: temporary.path
			)
			let destination = directory.appendingPathComponent("manifest.json")
			guard rename(
				temporary.path,
				destination.path
			) == 0
			else
			{
				try? FileManager.default.removeItem(at: temporary)
				return false
			}
			return true
		}
		catch
		{
			return false
		}
	}

	func load() -> [GitTurnBaselineRecord]
	{
		guard (try? requireDirectory(root)) != nil,
				let children = try? FileManager.default.contentsOfDirectory(
				at: root,
				includingPropertiesForKeys: nil
				)
		else
		{
			return []
		}
		var records: [GitTurnBaselineRecord] = []
		for child in children
		{
			if child.lastPathComponent.hasPrefix("comparison-"),
				UUID(uuidString: String(child.lastPathComponent.dropFirst("comparison-".count))) !=
				nil
			{
				removeDirectory(child)
				continue
			}
			guard let id = UUID(uuidString: child.lastPathComponent)
			else
			{
				continue
			}
			guard let record = restoredRecord(
				in: child,
				identity: id
			)
			else
			{
				remove(id)
				continue
			}
			records.append(record)
		}
		return records
	}

	private func restoredRecord(
		in directory: URL,
		identity id: UUID
	) -> GitTurnBaselineRecord?
	{
		guard (try? requireDirectory(directory)) != nil,
				let bytes = try? readRegular(
				directory.appendingPathComponent("manifest.json"),
				maximum: Self.maximumMetadataBytes
				),
				let record = try? JSONDecoder().decode(
				GitTurnBaselineRecord.self,
				from: bytes
				),
				record.reference.identity.id == id,
				record.reference.trackedFileCount == record.entries.count,
				record.entries.count <= limits.maximumPaths,
				record.reference.byteCount >= 0,
				record.reference.byteCount <= limits.maximumCaptureBytes,
				validRecord(record),
				Set(record.entries.map(\.path)).count == record.entries.count,
				record.entries.allSatisfy(
				{
					validPath($0.path)
				}
				),
				record.reference.acceptedTurnID?.isEmpty == false
		else
		{
			return nil
		}
		return record
	}

	private func validRecord(_ record: GitTurnBaselineRecord) -> Bool
	{
		guard record.reference.trackedFileCount >= 0,
				!record.reference.identity.threadID.isEmpty,
				record.reference.identity.repositoryRoot.hasPrefix("/")
		else
		{
			return false
		}
		var total = 0
		for entry in record.entries
		{
			guard entry.byteCount >= 0, entry.byteCount <= limits.maximumFileBytes,
					entry.byteCount <= limits.maximumCaptureBytes - total
			else
			{
				return false
			}
			if entry.kind == .missing
			{
				guard entry.byteCount == 0, entry.digest.isEmpty,
						!entry.executable
				else
				{
					return false
				}
			}
			else
			{
				guard entry.digest.count == 64,
						entry.digest.allSatisfy(
						{
							$0.isHexDigit
						}
						)
				else
				{
					return false
				}
			}
			total += entry.byteCount
		}
		return total == record.reference.byteCount
	}

	func remove(_ id: UUID)
	{
		removeDirectory(location(id))
	}

	private func validatedTree(_ record: GitTurnBaselineRecord) throws -> GitTurnBaselineTree
	{
		let directory = location(record.reference.identity.id).appendingPathComponent("before")
		let reader = GitTurnBaselineTreeReader(
			root: directory.path,
			limits: limits
		)
		let files = try record.entries.map
		{
			entry in
			let content = try reader.read(entry.path)
			guard content.entry == entry
			else
			{
				throw unavailable("The saved baseline is missing or has changed.")
			}
			return content
		}
		guard files.reduce(
			0,
			{
				$0 + $1.bytes.count
			}
		) == record.reference.byteCount
		else
		{
			throw unavailable("The saved baseline is incomplete.")
		}
		return GitTurnBaselineTree(
			files: files,
			indexManifest: record.indexManifest
		)
	}

	private func prepareStorage(outside repository: String) throws
	{
		let storagePath = WorkspaceFileIdentity.canonicalRootPath(root)
		guard storagePath != repository, !storagePath.hasPrefix(repository + "/")
		else
		{
			throw unavailable("Baseline storage must be outside the repository.")
		}
		try FileManager.default.createDirectory(
			at: root,
			withIntermediateDirectories: true,
			attributes: [.posixPermissions: 0o700]
		)
		try requireDirectory(root)
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o700],
			ofItemAtPath: root.path
		)
	}

	private func materialize(
		_ tree: GitTurnBaselineTree,
		at directory: URL
	) throws
	{
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: false,
			attributes: [.posixPermissions: 0o700]
		)
		for content in tree.files where content.entry.kind != .missing
		{
			try Task.checkCancellation()
			guard validPath(content.entry.path)
			else
			{
				throw unavailable("A saved path is invalid.")
			}
			let destination = directory.appendingPathComponent(content.entry.path)
			try FileManager.default.createDirectory(
				at: destination.deletingLastPathComponent(),
				withIntermediateDirectories: true,
				attributes: [.posixPermissions: 0o700]
			)
			try writeCapturedContent(
				content,
				to: destination
			)
		}
		freezeDirectories(directory)
	}

	private func writeCapturedContent(
		_ content: GitTurnBaselineContent,
		to destination: URL
	) throws
	{
		if content.entry.kind == .symbolicLink
		{
			guard let target = String(
				data: content.bytes,
				encoding: .utf8
			),
				!target.contains("\0")
			else
			{
				throw unavailable("A symbolic-link target has unsupported encoding.")
			}
			try FileManager.default.createSymbolicLink(
				atPath: destination.path,
				withDestinationPath: target
			)
		}
		else
		{
			try content.bytes.write(
				to: destination,
				options: .withoutOverwriting
			)
			try FileManager.default.setAttributes(
				[.posixPermissions: content.entry.executable ? 0o500 : 0o400],
				ofItemAtPath: destination.path
			)
		}
	}

	private func freezeDirectories(_ directory: URL)
	{
		setDirectoryPermissions(
			0o500,
			in: directory
		)
	}

	private func removeDirectory(_ directory: URL)
	{
		guard (try? requireDirectory(directory)) != nil
		else
		{
			return
		}
		setDirectoryPermissions(
			0o700,
			in: directory
		)
		try? FileManager.default.removeItem(at: directory)
	}

	private func setDirectoryPermissions(
		_ permissions: Int,
		in directory: URL
	)
	{
		let enumerator = FileManager.default.enumerator(
			at: directory,
			includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
			options: []
		)
		while let item = enumerator?.nextObject() as? URL
		{
			let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
			if values?.isDirectory == true && values?.isSymbolicLink != true
			{
				try? FileManager.default.setAttributes(
					[.posixPermissions: permissions],
					ofItemAtPath: item.path
				)
			}
		}
		try? FileManager.default.setAttributes(
			[.posixPermissions: permissions],
			ofItemAtPath: directory.path
		)
	}

	private func requireDirectory(_ directory: URL) throws
	{
		var metadata = stat()
		guard lstat(
			directory.path,
			&metadata
		) == 0, metadata.st_mode & S_IFMT == S_IFDIR
		else
		{
			throw unavailable("Baseline storage is unavailable.")
		}
	}

	private func readRegular(
		_ file: URL,
		maximum: Int
	) throws -> Data
	{
		let descriptor = open(
			file.path,
			O_RDONLY | O_NOFOLLOW | O_NONBLOCK
		)
		guard descriptor >= 0
		else
		{
			throw unavailable("Saved metadata is unavailable.")
		}
		defer
		{
			close(descriptor)
		}
		var metadata = stat()
		guard fstat(
			descriptor,
			&metadata
		) == 0,
			metadata.st_mode & S_IFMT == S_IFREG,
			metadata.st_size >= 0, metadata.st_size <= maximum
		else
		{
			throw unavailable("Saved metadata is invalid.")
		}
		let handle = FileHandle(
			fileDescriptor: descriptor,
			closeOnDealloc: false
		)
		let data = handle.readData(ofLength: maximum + 1)
		guard data.count <= maximum
		else
		{
			throw unavailable("Saved metadata is oversized.")
		}
		return data
	}

	private func location(_ id: UUID) -> URL
	{
		root.appendingPathComponent(
			id.uuidString,
			isDirectory: true
		)
	}

	private func unavailable(_ message: String) -> GitTurnBaselineReadError
	{
		.failure(.lastTurnBaselineUnavailable(message))
	}

	private func failure(_ error: Error) -> GitComparisonFailure
	{
		if error is CancellationError
		{
			return .cancelled
		}
		if let readError = error as? GitTurnBaselineReadError,
			case .failure(let failure) = readError
		{
			return failure
		}
		return .lastTurnBaselineUnavailable("The baseline could not be read or saved.")
	}

	private func validPath(_ path: String) -> Bool
	{
		GitTurnBaselineTreeReader.validPath(path)
	}
}
