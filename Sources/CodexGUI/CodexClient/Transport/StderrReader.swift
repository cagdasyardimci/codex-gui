import Darwin
import Foundation

final class StderrReader: @unchecked Sendable
{
	private static let maximumDrainBytes = 256 * 1024

	private let handle: FileHandle
	private let diagnostics: BackendDiagnosticsBuffer
	private let generation: UUID
	private let queue = DispatchQueue(label: "CodexGUI.AppServer.stderr")
	private var isFinished = false

	init(
		handle: FileHandle,
		diagnostics: BackendDiagnosticsBuffer,
		generation: UUID
	) throws
	{
		self.handle = handle
		self.diagnostics = diagnostics
		self.generation = generation
		let descriptor = handle.fileDescriptor
		let flags = fcntl(
			descriptor,
			F_GETFL
		)
		guard flags != -1, fcntl(
			descriptor,
			F_SETFL,
			flags | O_NONBLOCK
		) != -1
		else
		{
			throw AppServerError.protocolError("Could not configure the app-server stderr pipe.")
		}
	}

	func start()
	{
		let diagnostics = self.diagnostics
		let generation = self.generation
		handle.readabilityHandler =
		{
			[weak self] handle in
			guard let self
			else
			{
				return
			}
			self.queue.async
			{
				guard !self.isFinished
				else
				{
					return
				}
				Self.drain(
					handle,
					diagnostics: diagnostics,
					generation: generation,
					maximumBytes: Self.maximumDrainBytes
				)
			}
		}
	}

	func finish(
		exitCode: Int32,
		completion: @escaping @Sendable () -> Void
	)
	{
		handle.readabilityHandler = nil
		queue.async
		{
			guard !self.isFinished
			else
			{
				return
			}
			Self.drain(
				self.handle,
				diagnostics: self.diagnostics,
				generation: self.generation,
				maximumBytes: Self.maximumDrainBytes
			)
			self.diagnostics.recordExitCode(
				exitCode,
				for: self.generation
			)
			self.isFinished = true
			completion()
		}
	}

	func cancel()
	{
		handle.readabilityHandler = nil
		queue.async
		{
			self.isFinished = true
		}
	}

	private static func drain(
		_ handle: FileHandle,
		diagnostics: BackendDiagnosticsBuffer,
		generation: UUID,
		maximumBytes: Int
	)
	{
		let descriptor = handle.fileDescriptor
		var remainingBytes = maximumBytes
		var buffer = [UInt8](
			repeating: 0,
			count: 16 * 1024
		)
		while remainingBytes > 0
		{
			let bytesRead = buffer.withUnsafeMutableBytes
			{
				bytes in
				read(
					descriptor,
					bytes.baseAddress,
					min(
						bytes.count,
						remainingBytes
					)
				)
			}
			if bytesRead > 0
			{
				diagnostics.appendStderr(
					Data(buffer.prefix(bytesRead)),
					for: generation
				)
				remainingBytes -= bytesRead
			}
			else if bytesRead == -1, errno == EINTR
			{
				continue
			}
			else
			{
				return
			}
		}
	}
}
