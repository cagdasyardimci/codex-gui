import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct ReadAloudRuntimeTests
{
	@Test func segmentsWaitForBackendBoundaryAndDeviceDrainAndSilentSegmentsFinish() async throws
	{
		let service = ReadAloudTestService()
		let player = ReadAloudTestPlayer()
		let runtime = ReadAloudRuntime(
			service: service,
			makePlayer:
			{
				player
			}
		)
		let text = String(
			repeating: "A spoken phrase. ",
			count: 45
		)
		let parts = try ReadAloudTextSegments.make(text)
		service.silentAppendNumbers = [2]
		var finishes = player.finishes.stream.makeAsyncIterator()
		var completed = false
		let task = Task
		{
			try await runtime.play(request(text))
			{
			}; completed = true
		}
		defer
		{
			task.cancel(); runtime.cancel()
		}
		for index in parts.indices where index != 1
		{
			try #require(await finishes.next() != nil)
			#expect(!completed)
			#expect(service.appended.count == index + 1)
			#expect(service.retired.isEmpty)
			player.onDrained?()
		}
		try await task.value
		#expect(completed && service.appended == parts)
		#expect(service.appended.joined() == text)
		#expect(service.retired == ["private-audio"])
		#expect(service.onReadAloudEvent == nil && player.stopCount > 0)
	}

	@Test func cancellationCapturesLatePrivateThreadReceiptWithoutStartingSpeech() async throws
	{
		let service = ReadAloudTestService()
		service.suspendCreation = true
		let player = ReadAloudTestPlayer()
		let runtime = ReadAloudRuntime(
			service: service,
			makePlayer:
			{
				player
			}
		)
		var creations = service.creations.stream.makeAsyncIterator()
		let task = Task
		{
			try await runtime.play(request("Text"))
			{
			}
		}
		defer
		{
			task.cancel(); runtime.cancel(); service.creationReceipt?
				.resume(throwing: CancellationError()); service.creationReceipt = nil
		}
		try #require(await creations.next() != nil)
		task.cancel()
		let receipt = try #require(service.creationReceipt)
		service.creationReceipt = nil
		receipt.resume(returning: "private-audio")
		do
		{
			try await task.value; Issue.record("Cancelled playback unexpectedly completed")
		}
		catch
		{
			#expect(error is CancellationError)
		}
		#expect(service.started.isEmpty && service.appended.isEmpty)
		#expect(service.retired == ["private-audio"] && player.stopCount > 0)
	}

	@Test func incompatibleSessionAndForeignEventsNeverProducePlayback() async throws
	{
		let service = ReadAloudTestService()
		service.version = "v2"
		let player = ReadAloudTestPlayer()
		let runtime = ReadAloudRuntime(
			service: service,
			makePlayer:
			{
				player
			}
		)
		do
		{
			try await runtime.play(request("Text"))
			{
			}; Issue
			.record("V2 must not be used as literal read-aloud")
		}
		catch
		{
		}
		#expect(service.appended.isEmpty && player.enqueued == 0)
		#expect(service.retired == ["private-audio"])
	}

	private func request(_ text: String) -> ReadAloudRequest
	{
		ReadAloudRequest(
			context: OperationContext(
				workspace: WorkspaceIdentity(
					sessionID: UUID(),
					canonicalCheckoutPath: "/tmp/read-aloud"
				),
				generation: 0,
				requestID: UUID(),
				threadID: "original-chat"
			),
			entryID: "turn:answer",
			text: text
		)
	}
}

@MainActor
private final class ReadAloudTestService: ReadAloudService
{
	var onReadAloudEvent: ((String, ReadAloudBackendEvent) -> Void)?
	var suspendCreation = false
	var creationReceipt: CheckedContinuation<String, Error>?
	let creations = AsyncStream<Void>.makeStream()
	var version = "v3"
	var started: [String] = []
	var appended: [String] = []
	var retired: [String] = []
	var silentAppendNumbers: Set<Int> = []
	func readAloudAvailable(in directory: URL) async throws -> Bool
	{
		true
	}
	func createReadAloudThread(in directory: URL) async throws -> String
	{
		if suspendCreation
		{
			return try await withCheckedThrowingContinuation
			{
				creationReceipt = $0; creations.continuation.yield(())
			}
		}
		return "private-audio"
	}
	func startReadAloudSession(
		threadID: String,
		voice: String?
	) async throws
	{
		started.append(threadID)
		onReadAloudEvent?("foreign-chat", .failed("Must be ignored"))
		onReadAloudEvent?(threadID, .started(version: version))
	}
	func appendReadAloudSpeech(
		threadID: String,
		text: String
	) async throws
	{
		appended.append(text)
		if !silentAppendNumbers.contains(appended.count)
		{
			let chunk = try ReadAloudAudioChunk(
				pcmData: Data([0, 0]),
				sampleRate: 24000,
				numChannels: 1
			)
			onReadAloudEvent?(threadID, .audio(chunk))
		}
		onReadAloudEvent?(threadID, .segmentFinished)
	}
	func retireReadAloudThread(threadID: String) async
	{
		retired.append(threadID)
	}
}

@MainActor
private final class ReadAloudTestPlayer: ReadAloudAudioPlaying
{
	var onDrained: (() -> Void)?
	let finishes = AsyncStream<Void>.makeStream()
	var enqueued = 0
	var stopCount = 0
	func enqueue(_ chunk: ReadAloudAudioChunk) throws
	{
		enqueued += 1
	}
	func finish()
	{
		finishes.continuation.yield(())
	}
	func stop()
	{
		stopCount += 1
	}
}
