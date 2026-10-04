import Darwin
import Foundation

/// One queue owns a connection's descriptor. The lock orders retirement with nonblocking writes.
/// Bounded polling lets a full pipe release retired work promptly.
final class ProtocolMessageWriter: @unchecked Sendable
{
	private let descriptor: Int32
	private let queue = DispatchQueue(label: "CodexGUI.AppServer.stdin")
	private let lock = NSLock()
	private static let retirementPollIntervalMilliseconds: Int32 = 50
	private let reportIOFailure: (@Sendable (ProtocolWriteFailure) -> Void)?
	private var isRetired = false
	private var isClosed = false

	init(
		handle: FileHandle,
		reportIOFailure: (@Sendable (ProtocolWriteFailure) -> Void)? = nil
	) throws
	{
		let descriptor = fcntl(
			handle.fileDescriptor,
			F_DUPFD_CLOEXEC,
			0
		)
		guard descriptor >= 0
		else
		{
			throw Self.ioError(errno)
		}
		let flags = fcntl(
			descriptor,
			F_GETFL
		)
		guard flags >= 0,
				fcntl(
				descriptor,
				F_SETFL,
				flags | O_NONBLOCK
				) >= 0,
				fcntl(
				descriptor,
				F_SETNOSIGPIPE,
				1
				) >= 0
		else
		{
			let error = Self.ioError(errno)
			Darwin.close(descriptor)
			throw error
		}
		self.descriptor = descriptor
		self.reportIOFailure = reportIOFailure
	}

	deinit
	{
		if !isClosed
		{
			Darwin.close(descriptor)
		}
	}

	func enqueue(
		_ value: ProtocolJSONValue,
		ticket: ProtocolWriteTicket = ProtocolWriteTicket()
	) -> ProtocolWriteTicket
	{
		queue.async
		{
			self.write(
				value,
				ticket: ticket
			)
		}
		return ticket
	}

	func retire()
	{
		lock.lock()
		guard !isRetired
		else
		{
			lock.unlock()
			return
		}
		isRetired = true
		lock.unlock()
		queue.async
		{
			guard !self.isClosed
			else
			{
				return
			}
			Darwin.close(self.descriptor)
			self.isClosed = true
		}
	}

	private func write(
		_ value: ProtocolJSONValue,
		ticket: ProtocolWriteTicket
	)
	{
		do
		{
			try checkOpen()
			try ticket.checkPending()
			let object = value.foundationValue
			guard JSONSerialization.isValidJSONObject(object)
			else
			{
				throw AppServerError
					.protocolError("An app-server message is not a valid JSON object.")
			}
			var data = try JSONSerialization.data(withJSONObject: object)
			data.append(0x0A)
			try write(
				data,
				ticket: ticket
			)
			ticket.succeed()
		}
		catch
		{
			let failure = ticket.fail(error)
			if failure.requiresDisconnect
			{
				retire()
			}
		}
	}

	private func write(
		_ data: Data,
		ticket: ProtocolWriteTicket
	) throws
	{
		while true
		{
			let outcome = try writeChunk(
				data,
				ticket: ticket
			)
			if outcome.finished
			{
				return
			}
			if outcome.written > 0 || outcome.errorCode == EINTR
			{
				continue
			}
			let shouldWaitForWritablePipe = outcome.written == -1
				&& (outcome.errorCode == EAGAIN || outcome.errorCode == EWOULDBLOCK)
			if shouldWaitForWritablePipe
			{
				try ticket.checkPending()
				var descriptor = pollfd(
					fd: self.descriptor,
					events: Int16(POLLOUT),
					revents: 0
				)
				let result = Darwin.poll(
					&descriptor,
					1,
					Self.retirementPollIntervalMilliseconds
				)
				if result >= 0 || errno == EINTR
				{
					continue
				}
				throw retireAfterIOFailure(
					Self.ioError(errno),
					ticket: ticket
				)
			}
			throw retireAfterIOFailure(
				Self.ioError(outcome.errorCode),
				ticket: ticket
			)
		}
	}

	/// Physical transport failure is independent of which result first completed its waiter.
	@discardableResult
	func retireAfterIOFailure(
		_ cause: Error,
		ticket: ProtocolWriteTicket
	) -> ProtocolWriteFailure
	{
		let completionFailure = ticket.fail(
			cause,
			requiresDisconnect: true
		)
		retire()
		reportIOFailure?(ProtocolWriteFailure(
			cause: cause,
			mayHaveBeenSent: ticket.mayHaveBeenSent,
			requiresDisconnect: true
		))
		return completionFailure
	}

	private func writeChunk(
		_ data: Data,
		ticket: ProtocolWriteTicket
	) throws -> (written: Int, errorCode: Int32, finished: Bool)
	{
		lock.lock()
		defer
		{
			lock.unlock()
		}
		guard !isRetired
		else
		{
			throw AppServerError.disconnected
		}
		return try ticket.writeChunk(
			data,
			to: descriptor
		)
	}

	private func checkOpen() throws
	{
		lock.lock()
		defer
		{
			lock.unlock()
		}
		guard !isRetired
		else
		{
			throw AppServerError.disconnected
		}
	}

	private static func ioError(_ code: Int32) -> Error
	{
		NSError(
			domain: NSPOSIXErrorDomain,
			code: Int(code)
		)
	}
}
