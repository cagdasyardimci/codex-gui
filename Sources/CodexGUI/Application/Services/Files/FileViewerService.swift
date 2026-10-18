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

final class FileSystemFileViewerService: FileViewerService, @unchecked Sendable
{
	static let maximumTextBytes = 8 * 1024 * 1024
	static let maximumReadBytes = 32 * 1024 * 1024
	static let maximumSearchFiles = 20_000
	static let maximumSearchResults = 500
	private let inventoryLock = NSLock()
	private var cachedInventory: SearchInventory?

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
			let inventory = try self.inventory(root: root)
			let paths = inventory.index.search(
				query,
				limit: resultLimit + 1
			)
			try Task.checkCancellation()
			return FileViewerSearchPage(
				results: Array(paths.prefix(resultLimit)).map
				{
					FileLocation(
						root: root,
						relativePath: $0
					)
				},
				isTruncated: inventory.isTruncated || paths.count > resultLimit,
				excludedDirectoryCount: inventory.excludedDirectoryCount
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
			let inventory = try self.inventory(root: root)
			var results: [FileViewerSearchResult] = []
			for path in inventory.index.files
			{
				try Task.checkCancellation()
				let location = FileLocation(
					root: root,
					relativePath: path
				)
				guard Self.matchesMask(
					location.relativePath,
					mask: mask
				)
				else
				{
					continue
				}
				guard let text = try? Self.searchText(location)
				else
				{
					continue
				}
				guard text.range(
					of: query,
					options: [.caseInsensitive, .literal]
				) != nil
				else
				{
					continue
				}
				let lineIndex = SourceLineIndex(text)
				let source = text as NSString
				for index in lineIndex.lineStarts.indices
				{
					try Task.checkCancellation()
					let line = source.substring(with: lineIndex.contentRange(atLineIndex: index))
					guard line.range(
						of: query,
						options: [.caseInsensitive, .literal]
					) != nil
					else
					{
						continue
					}
					if results.count == resultLimit
					{
						return FileViewerSearchPage(
							results: results,
							isTruncated: true,
							excludedDirectoryCount: inventory.excludedDirectoryCount
						)
					}
					results.append(FileViewerSearchResult(
						location: location,
						lineNumber: index + 1,
						lineText: line
					))
				}
			}
			try Task.checkCancellation()
			return FileViewerSearchPage(
				results: results,
				isTruncated: inventory.isTruncated,
				excludedDirectoryCount: inventory.excludedDirectoryCount
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
		let (data, metadata) = try FileSystemFileReader.read(
			at: location,
			maximumBytes: maximumReadBytes
		)
		let content: FileViewerContent
		let ext = location.fileURL.pathExtension.lowercased()
		let capabilities = FileContentCapabilities(path: location.relativePath)
		if data.isEmpty
		{
			content = .empty
		}
		else if capabilities == .rasterImage
		{
			content = validImageHeader(
				data,
				extension: ext
			) ? .image(data) : .unsupported
		}
		else if capabilities == .pdf
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
				|| !capabilities.hasSource
		)
	}

	/// Search needs current text bytes, but no document revision or media preview preparation.
	private static func searchText(_ location: FileLocation) throws -> String?
	{
		if !FileContentCapabilities(path: location.relativePath).hasSource
		{
			return nil
		}
		let (data, _) = try FileSystemFileReader.read(
			at: location,
			maximumBytes: maximumReadBytes
		)
		guard !data.contains(0)
		else
		{
			return nil
		}
		return String(
			data: data,
			encoding: .utf8
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
		case "bmp":
			return data.starts(with: Data("BM".utf8))
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
		let parts = try FileSystemFileReader.components(location.relativePath)
		guard let name = parts.last
		else
		{
			throw FileViewerFailure.invalidPath
		}
		let directory = FileLocation(
			root: location.root,
			relativePath: parts.dropLast().joined(separator: "/")
		)
		let dirFD = try FileSystemFileReader.openContained(
			directory,
			flags: O_RDONLY | O_DIRECTORY
		)
		defer
		{
			Darwin.close(dirFD)
		}
		let sourceFD = try FileSystemFileReader.openRegularFile(
			in: dirFD,
			name: name
		)
		defer
		{
			Darwin.close(sourceFD)
		}
		let (previous, metadata) = try FileSystemFileReader.readBytes(
			sourceFD,
			maximumBytes: maximumReadBytes
		)
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
			throw FileSystemFileReader.failure(errno)
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
			throw FileSystemFileReader.failure(errno)
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
					throw FileSystemFileReader.failure(errno)
				}
				offset += written
			}
		}
		guard fsync(tempFD) == 0
		else
		{
			throw FileSystemFileReader.failure(errno)
		}
		let verifyFD = try FileSystemFileReader.openRegularFile(
			in: dirFD,
			name: name
		)
		defer
		{
			Darwin.close(verifyFD)
		}
		let (current, currentMetadata) = try FileSystemFileReader.readBytes(
			verifyFD,
			maximumBytes: maximumReadBytes
		)
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
			throw FileSystemFileReader.failure(errno)
		}
		return revision(bytes)
	}

	private static func list(_ location: FileLocation) throws -> [FileViewerDirectoryEntry]
	{
		try directoryItems(at: location).map
		{
			item in FileViewerDirectoryEntry(
				location: FileLocation(
					root: location.root,
					relativePath: location.relativePath.isEmpty ? item.name
						: location.relativePath + "/" + item.name
				),
				isDirectory: item.isDirectory,
				isSymbolicLink: item.isSymbolicLink
			)
		}
	}

	private struct DirectoryItem
	{
		let name: String
		let isDirectory: Bool
		let isSymbolicLink: Bool
	}

	/// Read names and entry types once for browsing and recursive search.
	private static func directoryItems(at location: FileLocation) throws -> [DirectoryItem]
	{
		let fd = try FileSystemFileReader.openContained(
			location,
			flags: O_RDONLY | O_DIRECTORY
		)
		guard let directory = fdopendir(fd)
		else
		{
			Darwin.close(fd)
			throw FileSystemFileReader.failure(errno)
		}
		defer
		{
			closedir(directory)
		}
		var entries: [DirectoryItem] = []
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
			let type = item.pointee.d_type
			var isDirectory = type == UInt8(DT_DIR)
			var isSymbolicLink = type == UInt8(DT_LNK)
			if type == UInt8(DT_UNKNOWN)
			{
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
				isDirectory = metadata.st_mode & S_IFMT == S_IFDIR
				isSymbolicLink = metadata.st_mode & S_IFMT == S_IFLNK
			}
			entries.append(DirectoryItem(
				name: name,
				isDirectory: isDirectory,
				isSymbolicLink: isSymbolicLink
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

	private struct DirectoryStamp: Equatable
	{
		let relativePath: String
		let device: UInt64
		let inode: UInt64
		let modifiedSeconds: Int
		let modifiedNanoseconds: Int
		let changedSeconds: Int
		let changedNanoseconds: Int
	}

	private struct SearchInventory
	{
		let root: String
		let index: ProjectFileIndex
		let directories: [DirectoryStamp]
		let isTruncated: Bool
		let excludedDirectoryCount: Int
	}

	private static func stamp(_ location: FileLocation) throws -> DirectoryStamp
	{
		let fd = try FileSystemFileReader.openContained(
			location,
			flags: O_RDONLY | O_DIRECTORY
		)
		defer
		{
			Darwin.close(fd)
		}
		var metadata = stat()
		guard fstat(
			fd,
			&metadata
		) == 0
		else
		{
			throw FileSystemFileReader.failure(errno)
		}
		return DirectoryStamp(
			relativePath: location.relativePath,
			device: UInt64(metadata.st_dev),
			inode: UInt64(metadata.st_ino),
			modifiedSeconds: metadata.st_mtimespec.tv_sec,
			modifiedNanoseconds: metadata.st_mtimespec.tv_nsec,
			changedSeconds: metadata.st_ctimespec.tv_sec,
			changedNanoseconds: metadata.st_ctimespec.tv_nsec
		)
	}

	private func inventory(root: String) throws -> SearchInventory
	{
		let cached = inventoryLock.withLock
		{
			cachedInventory
		}
		if let cached, cached.root == root
		{
			var current = true
			for directory in cached.directories
			{
				try Task.checkCancellation()
				let location = FileLocation(
					root: root,
					relativePath: directory.relativePath
				)
				guard (try? Self.stamp(location)) == directory
				else
				{
					current = false
					break
				}
			}
			if current
			{
				return cached
			}
		}
		let rebuilt = try Self.buildInventory(root: root)
		try Task.checkCancellation()
		inventoryLock.withLock
		{
			cachedInventory = rebuilt
		}
		return rebuilt
	}

	private static func buildInventory(root: String) throws -> SearchInventory
	{
		var pending = [FileLocation(
			root: root,
			relativePath: ""
		)]
		var files: [String] = []
		var directories: [DirectoryStamp] = []
		var visited = 0
		var excluded = 0
		var truncated = false
		while let directory = pending.popLast()
		{
			try Task.checkCancellation()
			directories.append(try stamp(directory))
			for entry in try directoryItems(at: directory)
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
					truncated = true
					break
				}
				if entry.isSymbolicLink
				{
					continue
				}
				if entry.isDirectory
				{
					pending.append(FileLocation(
						root: root,
						relativePath: directory.relativePath.isEmpty ? entry.name
							: directory.relativePath + "/" + entry.name
					))
				}
				else
				{
					files.append(directory.relativePath.isEmpty ? entry.name
						: directory.relativePath + "/" + entry.name)
				}
			}
			if truncated
			{
				break
			}
		}
		return SearchInventory(
			root: root,
			index: ProjectFileIndex(files: files.sorted()),
			directories: directories,
			isTruncated: truncated,
			excludedDirectoryCount: excluded
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
