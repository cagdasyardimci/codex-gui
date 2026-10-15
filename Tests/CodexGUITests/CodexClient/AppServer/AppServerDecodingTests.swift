import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AppServerDecodingTests
{
	@Test func connectionChangeDuringDecodingRejectsTheCompletedValue() async throws
	{
		let server = AppServer()
		let gate = DecodingGate()
		defer
		{
			gate.release()
		}
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
		defer
		{
			decoding.cancel()
		}
		try await gate.awaitStart()
		server.disconnect()
		gate.release()
		do
		{
			_ = try await withTaskCancellationHandler
			{
				try await decoding.value
			}
			onCancel:
			{
				decoding.cancel()
				gate.release()
			}
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
		defer
		{
			gate.release()
		}
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
		defer
		{
			decoding.cancel()
		}
		try await gate.awaitStart()
		decoding.cancel()
		gate.release()
		do
		{
			_ = try await withTaskCancellationHandler
			{
				try await decoding.value
			}
			onCancel:
			{
				decoding.cancel()
				gate.release()
			}
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
		guard !Thread.isMainThread
		else
		{
			throw AppServerError.protocolError("Test decoding blocked the main thread")
		}
		// The explicit release controls the scenario. This fallback also frees an uncooperative
		// worker if the owner cannot progress or cancellation cannot reach the semaphore.
		guard completion.wait(timeout: .now() + .seconds(10)) == .success
		else
		{
			throw AppServerError.requestTimedOut("test decode gate")
		}
		return 42
	}

	func awaitStart() async throws
	{
		var arrivals = started.stream.makeAsyncIterator()
		let arrival: Void? = await arrivals.next()
		try Task.checkCancellation()
		try #require(
			arrival != nil,
			"The decoder did not reach its start checkpoint"
		)
	}

	func release()
	{
		started.continuation.finish()
		completion.signal()
	}
}
