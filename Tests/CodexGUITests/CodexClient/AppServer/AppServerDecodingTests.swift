import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct AppServerDecodingTests
{
	@Test func connectionChangeDuringDecodingRejectsTheCompletedValue() async throws
	{
		let server = AppServer()
		let gate = DecodingGate()
		let generation = server.connectionGeneration
		let decoding = Task
		{
			try await server.decodeProtocolPayload(
				ProtocolJSONPayload(value: [:]),
				generation: generation,
				priority: .utility
			)
			{
				_ in try gate.decode()
			}
		}
		await gate.awaitStart()
		server.disconnect()
		gate.release()
		do
		{
			_ = try await decoding.value
			Issue.record("A decoded value from the retired connection was accepted.")
		}
		catch AppServerError.disconnected
		{
		}
	}

	@Test func cancellationDuringDecodingRejectsAnUncooperativeDecoderResult() async throws
	{
		let server = AppServer()
		let gate = DecodingGate()
		let generation = server.connectionGeneration
		let decoding = Task
		{
			try await server.decodeProtocolPayload(
				ProtocolJSONPayload(value: [:]),
				generation: generation,
				priority: .userInitiated
			)
			{
				_ in try gate.decode()
			}
		}
		await gate.awaitStart()
		decoding.cancel()
		gate.release()
		do
		{
			_ = try await decoding.value
			Issue.record("A cancelled decode returned its completed value.")
		}
		catch is CancellationError
		{
		}
	}
}

/// The decoder pauses off the main actor so ownership can change deterministically.
private final class DecodingGate: @unchecked Sendable
{
	private let started = AsyncStream<Void>.makeStream()
	private let completion = DispatchSemaphore(value: 0)

	func decode() throws -> Int
	{
		started.continuation.yield(())
		started.continuation.finish()
		guard completion.wait(timeout: .now() + .seconds(5)) == .success
		else
		{
			throw AppServerError.requestTimedOut("test decode gate")
		}
		return 42
	}

	func awaitStart() async
	{
		for await _ in started.stream
		{
			return
		}
	}

	func release()
	{
		completion.signal()
	}
}
