import Darwin
import Foundation

struct FileReadSafetyFixture: Sendable
{
	let root: URL

	init() throws
	{
		root = FileManager.default.temporaryDirectory
			.appendingPathComponent("file-read-safety-\(UUID().uuidString)")
		try FileManager.default.createDirectory(
			at: root,
			withIntermediateDirectories: true
		)
	}

	func makePipe(named name: String) throws -> URL
	{
		let pipe = root.appendingPathComponent(name)
		guard mkfifo(
			pipe.path,
			0o600
		) == 0
		else
		{
			throw NSError(
				domain: NSPOSIXErrorDomain,
				code: Int(errno)
			)
		}
		return pipe
	}

	func makeSparseFile(
		named name: String,
		byteCount: Int64
	) throws -> URL
	{
		let file = root.appendingPathComponent(name)
		let descriptor = Darwin.open(
			file.path,
			O_WRONLY | O_CREAT | O_EXCL,
			0o600
		)
		guard descriptor >= 0
		else
		{
			throw NSError(
				domain: NSPOSIXErrorDomain,
				code: Int(errno)
			)
		}
		defer
		{
			Darwin.close(descriptor)
		}
		guard ftruncate(
			descriptor,
			off_t(byteCount)
		) == 0
		else
		{
			throw NSError(
				domain: NSPOSIXErrorDomain,
				code: Int(errno)
			)
		}
		return file
	}

	/// A regression must fail and release its reader instead of leaving a blocked test worker.
	/// Timer expiry alone is not a rescue: a writer must connect to an actual FIFO reader.
	static func rescueBlockedOpen(
		at pipe: URL,
		startDelay: Duration = .seconds(2),
		onWaitingForReader: (@Sendable () -> Void)? = nil
	) -> Task<Bool, Never>
	{
		Task.detached
		{
			do
			{
				try await Task.sleep(for: startDelay)
				while !Task.isCancelled
				{
					let descriptor = Darwin.open(
						pipe.path,
						O_WRONLY | O_NONBLOCK
					)
					if descriptor >= 0
					{
						Darwin.close(descriptor)
						return true
					}
					let code = errno
					guard code == ENXIO || code == EINTR
					else
					{
						return false
					}
					onWaitingForReader?()
					// The operation can be admitted after this watchdog's first attempt.
					try await Task.sleep(for: .milliseconds(10))
				}
			}
			catch
			{
				return false
			}
			return false
		}
	}
}
