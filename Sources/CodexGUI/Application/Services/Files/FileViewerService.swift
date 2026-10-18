import CryptoKit
import Darwin
import Foundation

protocol FileViewerService: Sendable
{
	func listDirectory(at location: FileLocation) async throws -> [FileViewerDirectoryEntry]
	func read(at location: FileLocation) async throws -> FileViewerRead
	func save(
		at location: FileLocation,
		text: String,
		expectedRevision: FileDiskRevision
	) async throws -> FileDiskRevision
	func filenameSearch(
		root: String,
		query: String,
		limit: Int
	) async throws -> FileViewerSearchPage<FileLocation>
	func contentSearch(
		root: String,
		query: String,
		mask: String?,
		limit: Int
	) async throws -> FileViewerSearchPage<FileViewerSearchResult>
}

struct FileSystemFileViewerService: FileViewerService
{
	static let maximumTextBytes = 8 * 1024 * 1024
	static let maximumReadBytes = 32 * 1024 * 1024
	static let maximumSearchFiles = 20_000
	static let maximumSearchResults = 500

	func listDirectory(at location: FileLocation) async throws -> [FileViewerDirectoryEntry]
	{
		let work = Task.detached
		{
			try Self.list(location)
		}
		return try await withTaskCancellationHandler
		{
			try await work.value
		} onCancel:
		{
			work.cancel()
		}
	}

	func read(at location: FileLocation) async throws -> FileViewerRead
	{
		let work = Task.detached
		{
			try Self.readFile(location)
		}
		return try await withTaskCancellationHandler
		{
			try await work.value
		} onCancel:
		{
			work.cancel()
		}
	}

	func save(
		at location: FileLocation,
		text: String,
		expectedRevision: FileDiskRevision
	) async throws -> FileDiskRevision
	{
		let work = Task.detached
		{
			try Self.writeFile(
				location,
				text: text,
				expected: expectedRevision
			)
		}
		return try await withTaskCancellationHandler
		{
			try await work.value
		} onCancel:
		{
			work.cancel()
		}
	}

	func filenameSearch(
		root: String,
		query: String,
		limit: Int
	) async throws -> FileViewerSearchPage<FileLocation>
	{
		let work = Task.detached
		{
			let resultLimit = min(
				max(
					0,
					limit
				),
				Self.maximumSearchResults
			)
			let (files, truncated, excluded) = try Self.inventory(root: root)
			let index = ProjectFileIndex(files: files.map(\.relativePath))
			let paths = index.search(
				query,
				limit: resultLimit + 1
			)
			return FileViewerSearchPage(
				results: Array(paths.prefix(resultLimit)).map
				{
					FileLocation(
						root: root,
						relativePath: $0
					)
				},
				isTruncated: truncated || paths.count > resultLimit,
				excludedDirectoryCount: excluded
			)
		}
		return try await withTaskCancellationHandler
		{
			try await work.value
		} onCancel:
		{
			work.cancel()
		}
	}

	func contentSearch(
		root: String,
		query: String,
		mask: String?,
		limit: Int
	) async throws -> FileViewerSearchPage<FileViewerSearchResult>
	{
		let work = Task.detached
		{
			let resultLimit = min(
				max(
					0,
					limit
				),
				Self.maximumSearchResults
			)
			guard !query.isEmpty, resultLimit > 0
			else
			{
				return FileViewerSearchPage<FileViewerSearchResult>(
					results: [],
					isTruncated: false
				)
			}
			let (files, inventoryTruncated, excluded) = try Self.inventory(root: root)
			var results: [FileViewerSearchResult] = []
			for location in files
			{
				try Task.checkCancellation()
				guard Self.matchesMask(
					location.relativePath,
					mask: mask
				)
				else
				{
					continue
				}
				guard let loaded = try? Self.readFile(location),
						case .text(let text) = loaded.content
				else
				{
					continue
				}
				let lines = SourceLineIndex(text).lines
				for (index, line) in lines.enumerated()
					where line.range(
						of: query,
						options: [.caseInsensitive, .literal]
					) != nil
				{
					if results.count == resultLimit
					{
						return FileViewerSearchPage(
							results: results,
							isTruncated: true,
							excludedDirectoryCount: excluded
						)
					}
					results.append(FileViewerSearchResult(
						location: location,
						lineNumber: index + 1,
						lineText: line
					))
				}
			}
			return FileViewerSearchPage(
				results: results,
				isTruncated: inventoryTruncated,
				excludedDirectoryCount: excluded
			)
		}
		return try await withTaskCancellationHandler
		{
			try await work.value
		} onCancel:
		{
			work.cancel()
		}
	}

	private static func components(_ relative: String) throws -> [String]
	{
		if relative.isEmpty
		{
			return []
		}
		let parts = relative.split(
			separator: "/",
			omittingEmptySubsequences: false
		)
		.map(String.init)
		guard !relative.hasPrefix("/"),
				parts.allSatisfy(
				{
					!$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\0")
				}
				)
		else
		{
			throw FileViewerFailure.invalidPath
		}
		return parts
	}

	private static func openContained(
		_ location: FileLocation,
		flags: Int32
	) throws -> Int32
	{
		let parts = try components(location.relativePath)
		guard !location.root.isEmpty, location.root.hasPrefix("/")
		else
		{
			throw FileViewerFailure.invalidPath
		}
		var descriptor = Darwin.open(
			location.root,
			O_RDONLY | O_DIRECTORY | O_NOFOLLOW
		)
		guard descriptor >= 0
		else
		{
			throw failure(errno)
		}
		for (index, component) in parts.enumerated()
		{
			let next = component.withCString
			{
				openat(
					descriptor,
					$0,
					index == parts
						.count - 1 ? flags | O_NOFOLLOW : O_RDONLY | O_DIRECTORY | O_NOFOLLOW
				)
			}
			let code = errno
			Darwin.close(descriptor)
			guard next >= 0
			else
			{
				throw failure(code)
			}
			descriptor = next
		}
		return descriptor
	}

	private static func failure(_ code: Int32) -> FileViewerFailure
	{
		switch code
		{
		case ENOENT, ENOTDIR:
			return .unavailable
		case ELOOP:
			return .invalidPath
		case EACCES, EPERM:
			return .readOnly
		default:
			return .io(String(cString: strerror(code)))
		}
	}

	private static func readBytes(_ descriptor: Int32) throws -> (Data, stat)
	{
		var metadata = stat()
		guard fstat(
			descriptor,
			&metadata
		) == 0
		else
		{
			throw failure(errno)
		}
		guard (metadata.st_mode & S_IFMT) == S_IFREG
		else
		{
			throw FileViewerFailure.invalidPath
		}
		guard metadata.st_size <= maximumReadBytes
		else
		{
			throw FileViewerFailure.tooLarge
		}
		var data = Data()
		var buffer = [UInt8](
			repeating: 0,
			count: 64 * 1024
		)
		while true
		{
			try Task.checkCancellation()
			let count = Darwin.read(
				descriptor,
				&buffer,
				buffer.count
			)
			guard count >= 0
			else
			{
				throw failure(errno)
			}
			if count == 0
			{
				break
			}
			guard data.count + count <= maximumReadBytes
			else
			{
				throw FileViewerFailure.tooLarge
			}
			data.append(contentsOf: buffer.prefix(count))
		}
		return (data, metadata)
	}

	private static func revision(_ data: Data) -> FileDiskRevision
	{
		FileDiskRevision(
			digest: SHA256.hash(data: data).map
			{
				String(
					format: "%02x",
					$0
				)
			}.joined(),
			byteCount: data.count
		)
	}

	private static func readFile(_ location: FileLocation) throws -> FileViewerRead
	{
		let fd = try openContained(
			location,
			flags: O_RDONLY
		)
		defer
		{
			Darwin.close(fd)
		}
		let (data, metadata) = try readBytes(fd)
		let content: FileViewerContent
		let ext = location.fileURL.pathExtension.lowercased()
		let imageExtensions = ["png", "jpg", "jpeg", "gif", "tif", "tiff", "heic", "webp"]
		let isMedia = imageExtensions.contains(ext) || ext == "pdf"
		if data.isEmpty
		{
			content = .empty
		}
		else if imageExtensions.contains(ext)
		{
			content = validImageHeader(
				data,
				extension: ext
			) ? .image(data) : .unsupported
		}
		else if ext == "pdf"
		{
			content = data.starts(with: Data("%PDF-".utf8)) ? .pdf(data) : .unsupported
		}
		else if data.contains(0)
		{
			throw FileViewerFailure.binary
		}
		else if let text = String(
			data: data,
			encoding: .utf8
		)
		{
			content = .text(text)
		}
		else
		{
			throw FileViewerFailure.unsupportedEncoding
		}
		return FileViewerRead(
			content: content,
			revision: revision(data),
			isReadOnly: metadata.st_mode & 0o222 == 0 || data.count > maximumTextBytes
				|| isMedia
		)
	}

	private static func validImageHeader(
		_ data: Data,
		extension ext: String
	) -> Bool
	{
		switch ext
		{
		case "png":
			return data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10])
		case "jpg", "jpeg":
			return data.starts(with: [255, 216, 255])
		case "gif":
			return data.starts(with: Data("GIF8".utf8))
		case "tif", "tiff":
			return data.starts(with: [73, 73, 42, 0]) || data.starts(with: [77, 77, 0, 42])
		case "webp":
			return data.count >= 12 && data.starts(with: Data("RIFF".utf8))
				&& data.subdata(in: 8 ..< 12) == Data("WEBP".utf8)
		case "heic":
			return data.count >= 12 && data.subdata(in: 4 ..< 8) == Data("ftyp".utf8)
		default:
			return false
		}
	}

	private static func writeFile(
		_ location: FileLocation,
		text: String,
		expected: FileDiskRevision
	) throws -> FileDiskRevision
	{
		let bytes = Data(text.utf8)
		guard bytes.count <= maximumTextBytes
		else
		{
			throw FileViewerFailure.tooLarge
		}
		let parts = try components(location.relativePath)
		guard let name = parts.last
		else
		{
			throw FileViewerFailure.invalidPath
		}
		let directory = FileLocation(
			root: location.root,
			relativePath: parts.dropLast().joined(separator: "/")
		)
		let dirFD = try openContained(
			directory,
			flags: O_RDONLY | O_DIRECTORY
		)
		defer
		{
			Darwin.close(dirFD)
		}
		let sourceFD = name.withCString
		{
			openat(
				dirFD,
				$0,
				O_RDONLY | O_NOFOLLOW
			)
		}
		guard sourceFD >= 0
		else
		{
			throw failure(errno)
		}
		defer
		{
			Darwin.close(sourceFD)
		}
		let (previous, metadata) = try readBytes(sourceFD)
		guard revision(previous) == expected
		else
		{
			throw FileViewerFailure.conflict
		}
		guard metadata.st_mode & 0o222 != 0
		else
		{
			throw FileViewerFailure.readOnly
		}
		try Task.checkCancellation()
		let temporary = ".codex-files-\(UUID().uuidString)"
		let tempFD = temporary.withCString
		{
			openat(
				dirFD,
				$0,
				O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
				0o600
			)
		}
		guard tempFD >= 0
		else
		{
			throw failure(errno)
		}
		defer
		{
			temporary.withCString
			{
				_ = unlinkat(
					dirFD,
					$0,
					0
				)
			}
		}
		defer
		{
			Darwin.close(tempFD)
		}
		guard fchmod(
			tempFD,
			metadata.st_mode & 0o7777
		) == 0
		else
		{
			throw failure(errno)
		}
		try bytes.withUnsafeBytes
		{
			raw in
			var offset = 0
			while offset < raw.count
			{
				let written = Darwin.write(
					tempFD,
					raw.baseAddress!.advanced(by: offset),
					raw.count - offset
				)
				guard written > 0
				else
				{
					throw failure(errno)
				}
				offset += written
			}
		}
		guard fsync(tempFD) == 0
		else
		{
			throw failure(errno)
		}
		let verifyFD = name.withCString
		{
			openat(
				dirFD,
				$0,
				O_RDONLY | O_NOFOLLOW
			)
		}
		guard verifyFD >= 0
		else
		{
			throw failure(errno)
		}
		defer
		{
			Darwin.close(verifyFD)
		}
		let (current, currentMetadata) = try readBytes(verifyFD)
		guard revision(current) == expected,
				currentMetadata.st_dev == metadata.st_dev,
				currentMetadata.st_ino == metadata.st_ino
		else
		{
			throw FileViewerFailure.conflict
		}
		try Task.checkCancellation()
		// Recheck immediately before replacement. Other processes need not cooperate
		// with this check.
		let renamed = temporary.withCString
		{
			temp in name.withCString
			{
				final in renameat(
					dirFD,
					temp,
					dirFD,
					final
				)
			}
		}
		guard renamed == 0
		else
		{
			throw failure(errno)
		}
		return revision(bytes)
	}

	private static func list(_ location: FileLocation) throws -> [FileViewerDirectoryEntry]
	{
		let fd = try openContained(
			location,
			flags: O_RDONLY | O_DIRECTORY
		)
		guard let directory = fdopendir(fd)
		else
		{
			Darwin.close(fd)
			throw failure(errno)
		}
		defer
		{
			closedir(directory)
		}
		var entries: [FileViewerDirectoryEntry] = []
		while let item = readdir(directory)
		{
			try Task.checkCancellation()
			let name = withUnsafePointer(to: item.pointee.d_name)
			{
				$0.withMemoryRebound(
					to: CChar.self,
					capacity: Int(MAXNAMLEN) + 1
				)
				{
					String(cString: $0)
				}
			}
			if name == "." || name == ".."
			{
				continue
			}
			var metadata = stat()
			let result = name.withCString
			{
				fstatat(
					fd,
					$0,
					&metadata,
					AT_SYMLINK_NOFOLLOW
				)
			}
			if result != 0
			{
				continue
			}
			entries.append(FileViewerDirectoryEntry(
				location: FileLocation(
					root: location.root,
					relativePath: ([location.relativePath, name].filter
					{
						!$0.isEmpty
					})
					.joined(separator: "/")
				),
				isDirectory: metadata.st_mode & S_IFMT == S_IFDIR,
				isSymbolicLink: metadata.st_mode & S_IFMT == S_IFLNK
			))
		}
		return entries.sorted
		{
			if $0.isDirectory != $1.isDirectory
			{
				return $0.isDirectory
			}
			return $0.name.localizedStandardCompare($1.name) == .orderedAscending
		}
	}

	private static func inventory(root: String) throws -> ([FileLocation], Bool, Int)
	{
		var pending = [FileLocation(
			root: root,
			relativePath: ""
		)]
		var files: [FileLocation] = []
		var visited = 0
		var excluded = 0
		while let directory = pending.popLast()
		{
			try Task.checkCancellation()
			for entry in try list(directory)
			{
				if entry.isDirectory,
					GeneratedProjectDirectoryPolicy.excludes(entry.name)
				{
					excluded += 1
					continue
				}
				visited += 1
				if visited > maximumSearchFiles
				{
					return (files, true, excluded)
				}
				if entry.isSymbolicLink
				{
					continue
				}
				if entry.isDirectory
				{
					pending.append(entry.location)
				}
				else
				{
					files.append(entry.location)
				}
			}
		}
		return (
			files.sorted
			{
				$0.relativePath < $1.relativePath
			},
			false,
			excluded
		)
	}

	private static func matchesMask(
		_ path: String,
		mask: String?
	) -> Bool
	{
		guard let mask, !mask.isEmpty
		else
		{
			return true
		}
		let name = URL(fileURLWithPath: path).lastPathComponent
		return maskAlternatives(mask).contains
		{
			pattern in
			if pattern.hasPrefix("**/")
			{
				let suffix = String(pattern.dropFirst(3))
				if fnmatch(
					suffix,
					name,
					FNM_CASEFOLD
				) == 0
				{
					return true
				}
				let components = path.split(separator: "/")
				return components.indices.contains
				{
					fnmatch(
						suffix,
						components[$0...].joined(separator: "/"),
						FNM_CASEFOLD
					) == 0
				}
			}
			return fnmatch(
				pattern,
				pattern.contains("/") ? path : name,
				FNM_CASEFOLD
			) == 0
		}
	}

	private static func maskAlternatives(_ mask: String) -> [String]
	{
		guard let open = mask.firstIndex(of: "{"),
				let close = mask[open...].firstIndex(of: "}")
		else
		{
			return mask.split(separator: ",").map
			{
				$0.trimmingCharacters(in: .whitespaces)
			}
		}
		let prefix = String(mask[..<open])
		let suffix = String(mask[mask.index(after: close)...])
		return mask[mask.index(after: open) ..< close].split(separator: ",").prefix(32).map
		{
			prefix + $0.trimmingCharacters(in: .whitespaces) + suffix
		}
	}
}
