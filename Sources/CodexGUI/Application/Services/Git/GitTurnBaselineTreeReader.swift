import CryptoKit
import Darwin
import Foundation

struct GitTurnBaselineTreeReader
{
	let root: String
	let limits: GitTurnBaselineLimits

	func capture(additionalPaths: [String] = []) throws -> GitTurnBaselineTree
	{
		try Task.checkCancellation()
		let commands = GitTurnBaselineGitCommands(
			root: root,
			maximumBytes: limits.maximumCaptureBytes
		)
		let check = try? commands.run(["rev-parse", "--is-inside-work-tree"])
		try Task.checkCancellation()
		guard let check,
				String(
				decoding: check,
				as: UTF8.self
				)
				.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
		else
		{
			throw GitTurnBaselineReadError.failure(.notGitRepository)
		}
		var manifests = GitTurnBaselineManifestReader(commands: commands)
		let before = try manifests.read()
		let paths = Set(before.paths + additionalPaths).sorted()
		guard paths.count <= limits.maximumPaths
		else
		{
			throw unavailable("Tracked-file count exceeds the capture limit.")
		}
		let first = try readAll(paths)
		let second = try readAll(paths)
		let after = try manifests.read()
		guard before == after, first == second
		else
		{
			throw GitTurnBaselineReadError.failure(.repositoryChanged)
		}
		return GitTurnBaselineTree(
			files: first,
			indexManifest: before.index
		)
	}

	private func readAll(_ paths: [String]) throws -> [GitTurnBaselineContent]
	{
		var bytes = 0
		return try paths.map
		{
			path in
			try Task.checkCancellation()
			let content = try read(path)
			bytes += content.bytes.count
			guard bytes <= limits.maximumCaptureBytes
			else
			{
				throw unavailable("Tracked content exceeds the 64 MiB capture limit.")
			}
			return content
		}
	}

	func read(_ path: String) throws -> GitTurnBaselineContent
	{
		try Task.checkCancellation()
		guard Self.validPath(path)
		else
		{
			throw unavailable("A tracked path is invalid.")
		}
		var directory = open(
			root,
			O_RDONLY | O_DIRECTORY | O_NOFOLLOW
		)
		guard directory >= 0
		else
		{
			throw unavailable("The repository directory is unavailable.")
		}
		defer
		{
			close(directory)
		}
		let components = path.split(separator: "/").map(String.init)
		for component in components.dropLast()
		{
			let child = openat(
				directory,
				component,
				O_RDONLY | O_DIRECTORY | O_NOFOLLOW
			)
			guard child >= 0
			else
			{
				if errno == ENOENT || errno == ENOTDIR || errno == ELOOP
				{
					return missing(path)
				}
				throw unavailable("A tracked directory could not be read.")
			}
			close(directory)
			directory = child
		}
		let name = components.last!
		var metadata = stat()
		guard fstatat(
			directory,
			name,
			&metadata,
			AT_SYMLINK_NOFOLLOW
		) == 0
		else
		{
			if errno == ENOENT || errno == ENOTDIR
			{
				return missing(path)
			}
			throw unavailable("A tracked file could not be inspected.")
		}
		let kind = metadata.st_mode & S_IFMT
		if kind == S_IFDIR
		{
			return missing(path)
		}
		guard metadata.st_size >= 0, metadata.st_size <= limits.maximumFileBytes
		else
		{
			throw unavailable("A tracked file exceeds the 8 MiB capture limit.")
		}
		let data: Data
		let fileKind: GitTurnBaselineEntry.Kind
		if kind == S_IFLNK
		{
			data = try readSymbolicLink(
				in: directory,
				name: name,
				metadata: metadata
			)
			fileKind = .symbolicLink
		}
		else if kind == S_IFREG
		{
			data = try readRegularFile(
				in: directory,
				name: name,
				metadata: &metadata
			)
			fileKind = .regular
		}
		else
		{
			throw unavailable("A tracked special file cannot be captured.")
		}
		var final = stat()
		guard fstatat(
			directory,
			name,
			&final,
			AT_SYMLINK_NOFOLLOW
		) == 0, stable(
			metadata,
			final
		)
		else
		{
			throw GitTurnBaselineReadError.failure(.repositoryChanged)
		}
		let entry = GitTurnBaselineEntry(
			path: path,
			kind: fileKind,
			executable: fileKind == .regular && metadata.st_mode & 0o111 != 0,
			byteCount: data.count,
			digest: SHA256.hash(data: data).map
			{
				String(
					format: "%02x",
					$0
				)
			}.joined()
		)
		return GitTurnBaselineContent(
			entry: entry,
			bytes: data
		)
	}

	private func readSymbolicLink(
		in directory: Int32,
		name: String,
		metadata: stat
	) throws -> Data
	{
		let minimumLinkBufferSize = 4096
		let desiredLinkBufferSize = max(
			minimumLinkBufferSize,
			Int(metadata.st_size) + 1
		)
		let linkBufferSize = min(
			limits.maximumFileBytes + 1,
			desiredLinkBufferSize
		)
		var buffer = [UInt8](
			repeating: 0,
			count: linkBufferSize
		)
		let count = buffer.withUnsafeMutableBytes
		{
			readlinkat(
				directory,
				name,
				$0.baseAddress!.assumingMemoryBound(to: CChar.self),
				$0.count
			)
		}
		guard count >= 0, count < buffer.count
		else
		{
			throw unavailable("A symbolic-link target could not be captured.")
		}
		return Data(buffer.prefix(count))
	}

	private func readRegularFile(
		in directory: Int32,
		name: String,
		metadata: inout stat
	) throws -> Data
	{
		let descriptor = openat(
			directory,
			name,
			O_RDONLY | O_NOFOLLOW | O_NONBLOCK
		)
		guard descriptor >= 0
		else
		{
			throw unavailable("A tracked file could not be opened safely.")
		}
		defer
		{
			close(descriptor)
		}
		var opened = stat()
		guard fstat(
			descriptor,
			&opened
		) == 0, opened.st_mode & S_IFMT == S_IFREG,
			opened.st_dev == metadata.st_dev, opened.st_ino == metadata.st_ino
		else
		{
			throw GitTurnBaselineReadError.failure(.repositoryChanged)
		}
		let handle = FileHandle(
			fileDescriptor: descriptor,
			closeOnDealloc: false
		)
		let data = handle.readData(ofLength: limits.maximumFileBytes + 1)
		guard data.count <= limits.maximumFileBytes
		else
		{
			throw unavailable("A tracked file exceeds the 8 MiB capture limit.")
		}
		var after = stat()
		guard fstat(
			descriptor,
			&after
		) == 0, stable(
			opened,
			after
		), data.count == after.st_size
		else
		{
			throw GitTurnBaselineReadError.failure(.repositoryChanged)
		}
		metadata = after
		return data
	}

	static func validPath(_ path: String) -> Bool
	{
		let components = path.split(
			separator: "/",
			omittingEmptySubsequences: false
		)
		return !path.isEmpty && !path.hasPrefix("/") && !path.contains("\0")
			&& components.allSatisfy
			{
				!$0.isEmpty && $0 != "." && $0 != ".." && $0 != ".git"
			}
	}

	private func missing(_ path: String) -> GitTurnBaselineContent
	{
		GitTurnBaselineContent(
			entry: GitTurnBaselineEntry(
				path: path,
				kind: .missing,
				executable: false,
				byteCount: 0,
				digest: ""
			),
			bytes: Data()
		)
	}

	private func stable(
		_ before: stat,
		_ after: stat
	) -> Bool
	{
		before.st_dev == after.st_dev && before.st_ino == after.st_ino
			&& before.st_size == after.st_size && before.st_mode == after.st_mode
			&& before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec
			&& before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec
			&& before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec
			&& before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec
	}

	private func unavailable(_ message: String) -> GitTurnBaselineReadError
	{
		.failure(.lastTurnBaselineUnavailable(message))
	}
}
