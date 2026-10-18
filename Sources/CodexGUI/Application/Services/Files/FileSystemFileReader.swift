import Darwin
import Foundation

/// Contained descriptor walks and bounded reads shared by document and composer file inputs.
enum FileSystemFileReader
{
	static func components(_ relative: String) throws -> [String]
	{
		if relative.isEmpty
		{
			return []
		}
		// POSIX separators are bytes, even when a combining mark joins a slash grapheme.
		let parts = relative.utf8.split(
			separator: 0x2F,
			omittingEmptySubsequences: false
		)
		.map
		{
			String(
				decoding: $0,
				as: UTF8.self
			)
		}
		guard relative.utf8.first != 0x2F,
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

	static func openContained(
		_ location: FileLocation,
		flags: Int32
	) throws -> Int32
	{
		try Task.checkCancellation()
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
			let componentFlags = index == parts.count - 1
				? flags | O_NONBLOCK | O_NOFOLLOW : O_RDONLY | O_DIRECTORY | O_NOFOLLOW
			let next = component.withCString
			{
				openat(
					descriptor,
					$0,
					componentFlags
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

	static func failure(_ code: Int32) -> FileViewerFailure
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

	static func readBytes(
		_ descriptor: Int32,
		maximumBytes: Int
	) throws -> (Data, stat)
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
		guard metadata.st_size >= 0, metadata.st_size <= maximumBytes
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
				min(
					buffer.count,
					maximumBytes - data.count + 1
				)
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
			guard data.count + count <= maximumBytes
			else
			{
				throw FileViewerFailure.tooLarge
			}
			data.append(contentsOf: buffer.prefix(count))
		}
		return (data, metadata)
	}

	static func read(
		at location: FileLocation,
		maximumBytes: Int
	) throws -> (Data, stat)
	{
		let descriptor = try openContained(
			location,
			flags: O_RDONLY
		)
		defer
		{
			Darwin.close(descriptor)
		}
		return try readBytes(
			descriptor,
			maximumBytes: maximumBytes
		)
	}

	static func openRegularFile(
		in directory: Int32,
		name: String
	) throws -> Int32
	{
		let descriptor = name.withCString
		{
			openat(
				directory,
				$0,
				O_RDONLY | O_NOFOLLOW | O_NONBLOCK
			)
		}
		guard descriptor >= 0
		else
		{
			throw failure(errno)
		}
		var metadata = stat()
		guard fstat(
			descriptor,
			&metadata
		) == 0
		else
		{
			let code = errno
			Darwin.close(descriptor)
			throw failure(code)
		}
		guard metadata.st_mode & S_IFMT == S_IFREG
		else
		{
			Darwin.close(descriptor)
			throw FileViewerFailure.invalidPath
		}
		return descriptor
	}
}
