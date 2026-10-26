import Darwin
import Foundation

/// Its lock protects cancellation against each nonblocking write and completes all waiters once.
final class ProtocolWriteTicket: @unchecked Sendable
{
	private static let maximumWriteChunkSize = 16 * 1024
	private let lock = NSLock()
	private var bytesWritten = 0
	private var frameSize = 0
	private var result: Result<Void, ProtocolWriteFailure>?
	private var waiters: [CheckedContinuation<Void, Error>] = []
	private var completion: (@Sendable (Result<Void, ProtocolWriteFailure>) -> Void)?

	init(completion: (@Sendable (Result<Void, ProtocolWriteFailure>) -> Void)? = nil)
	{
		self.completion = completion
	}

	var mayHaveBeenSent: Bool
	{
		lock.lock()
		defer
		{
			lock.unlock()
		}
		return bytesWritten > 0
	}

	var hasIncompleteFrame: Bool
	{
		lock.lock()
		defer
		{
			lock.unlock()
		}
		return bytesWritten > 0 && bytesWritten < frameSize
	}

	func checkPending() throws
	{
		lock.lock()
		defer
		{
			lock.unlock()
		}
		if let result
		{
			try result.get()
		}
	}

	func writeChunk(
		_ data: Data,
		to descriptor: Int32
	) throws -> (written: Int, errorCode: Int32, finished: Bool)
	{
		lock.lock()
		defer
		{
			lock.unlock()
		}
		if let result
		{
			try result.get()
		}
		frameSize = data.count
		let count = min(
			Self.maximumWriteChunkSize,
			data.count - bytesWritten
		)
		let written = data.withUnsafeBytes
		{
			bytes in
			Darwin.write(
				descriptor,
				bytes.baseAddress!.advanced(by: bytesWritten),
				count
			)
		}
		let errorCode = written == 0 ? EIO : errno
		if written > 0
		{
			bytesWritten += written
		}
		return (written, errorCode, bytesWritten == data.count)
	}

	@discardableResult
	func fail(
		_ cause: Error,
		requiresDisconnect: Bool = false
	) -> ProtocolWriteFailure
	{
		lock.lock()
		if case .failure(let existing)? = result
		{
			lock.unlock()
			return existing
		}
		let failure = ProtocolWriteFailure(
			cause: cause,
			mayHaveBeenSent: bytesWritten > 0,
			requiresDisconnect: requiresDisconnect || (bytesWritten > 0 && bytesWritten < frameSize)
		)
		if result != nil
		{
			lock.unlock()
			return failure
		}
		result = .failure(failure)
		let waiting = waiters
		waiters.removeAll()
		let completed = completion
		completion = nil
		lock.unlock()
		for waiter in waiting
		{
			waiter.resume(throwing: failure)
		}
		completed?(.failure(failure))
		return failure
	}

	func succeed()
	{
		lock.lock()
		guard result == nil
		else
		{
			lock.unlock()
			return
		}
		result = .success(())
		let waiting = waiters
		waiters.removeAll()
		let completed = completion
		completion = nil
		lock.unlock()
		for waiter in waiting
		{
			waiter.resume()
		}
		completed?(.success(()))
	}

	func wait() async throws
	{
		try await withTaskCancellationHandler
		{
			try await withCheckedThrowingContinuation
			{
				continuation in
				lock.lock()
				if let result
				{
					lock.unlock()
					continuation.resume(with: result.mapError
					{
						$0 as Error
					})
				}
				else
				{
					waiters.append(continuation)
					lock.unlock()
				}
			}
		}
		onCancel:
		{
			self.fail(CancellationError())
		}
	}
}
