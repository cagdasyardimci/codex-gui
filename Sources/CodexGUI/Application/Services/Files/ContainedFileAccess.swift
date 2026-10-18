import Darwin
import Foundation

/// Opens paths below one captured root without following links.
/// Byte reads accept only regular files and enforce the caller's limit.
enum ContainedFileAccess
{
	static func read(
		_ location: FileLocation,
		maximumBytes: Int
	) throws -> (Data, stat)
	{
		try Task.checkCancellation()
		let descriptor = try open(
			location,
			flags: O_RDONLY
		)
		defer
		{
			Darwin.close(descriptor)
		}
		return try read(
			descriptor,
			maximumBytes: maximumBytes
		)
	}

	static func components(_ relative: String) throws -> [String]
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

	static func open(
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
						.count - 1 ? flags | O_NOFOLLOW | O_NONBLOCK
						: O_RDONLY | O_DIRECTORY | O_NOFOLLOW
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

	static func read(
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
		data.reserveCapacity(Int(metadata.st_size))
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
			guard data.count + count <= maximumBytes
			else
			{
				throw FileViewerFailure.tooLarge
			}
			data.append(contentsOf: buffer.prefix(count))
		}
		return (data, metadata)
	}

}
