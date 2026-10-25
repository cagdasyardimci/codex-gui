import Darwin
import Foundation
import Testing
@testable import CodexGUI

@Suite
struct ProtocolMessageWriterTests
{
	@Test func orderedFramesPreserveUnicodeNumbersAndMutableInputSnapshot() async throws
	{
		let pipe = Pipe()
		let writer = try ProtocolMessageWriter(handle: pipe.fileHandleForWriting)
		defer
		{
			writer.retire()
		}
		let reading = readToEnd(pipe.fileHandleForReading)
		let mutable = NSMutableDictionary(dictionary: ["text": "original"])
		let snapshot = try ProtocolJSONValue(snapshot: ["nested": mutable])
		mutable["text"] = "changed"
		var tickets = [writer.enqueue(snapshot)]
		let text = String(
			repeating: "e\u{0301}🧪\u{2028}\n",
			count: 300
		)
		for index in 0 ..< 24
		{
			tickets.append(writer.enqueue(try ProtocolJSONValue(snapshot: [
				"index": index,
				"text": text,
				"bool": true,
				"largeInteger": NSNumber(value: Int64(9_007_199_254_740_993)),
				"null": NSNull(),
			])))
		}
		for ticket in tickets
		{
			try await ticket.wait()
		}
		writer.retire()
		try pipe.fileHandleForWriting.close()
		let frames = try frames(in: await reading.value)
		#expect(frames.count == 25)
		#expect((frames[0]["nested"] as? [String: String])?["text"] == "original")
		for (index, frame) in frames.dropFirst().enumerated()
		{
			#expect(frame["index"] as? Int == index)
			#expect((frame["text"] as? String)?.utf8.elementsEqual(text.utf8) == true)
			#expect(frame["bool"] as? Bool == true)
			#expect(JSONRPCRequestID(json: frame["bool"]!) == nil)
			#expect(JSONRPCRequestID(json: frame["largeInteger"]!)
				== .integer(9_007_199_254_740_993))
			#expect(frame["null"] is NSNull)
		}
	}

	@MainActor
	@Test func fullPipeKeepsMainActorResponsiveAndQueuedCancellationSendsNoBytes() async throws
	{
		let pipe = Pipe()
		let writer = try ProtocolMessageWriter(handle: pipe.fileHandleForWriting)
		defer
		{
			writer.retire()
			try? pipe.fileHandleForWriting.close()
			try? pipe.fileHandleForReading.close()
		}
		let active = writer.enqueue(.object(["large": .string(String(
			repeating: "x",
			count: 1_048_576
		))]))
		try await waitUntil
		{
			active.hasIncompleteFrame
		}
		let queued = writer.enqueue(.object(["mustNotSend": .string("queued")]))
		let cancelled = queued.fail(CancellationError())
		#expect(!cancelled.mayHaveBeenSent)
		#expect(!cancelled.requiresDisconnect)
		var mainActorAdvanced = false
		let pulse = Task
		{
			mainActorAdvanced = true
		}
		await pulse.value
		#expect(mainActorAdvanced)
		let partial = active.fail(CancellationError())
		#expect(partial.mayHaveBeenSent)
		#expect(partial.requiresDisconnect)
		await expectFailure(
			active,
			mayHaveBeenSent: true
		)
		await expectFailure(
			queued,
			mayHaveBeenSent: false
		)
		let afterRetirement = writer.enqueue(.object(["late": .string("never")]))
		await expectFailure(
			afterRetirement,
			mayHaveBeenSent: false
		)
	}

	@Test func terminalIOFailureRetiresWriterAfterCancellationAlreadyCompletedTicket() async throws
	{
		let pipe = Pipe()
		let recording = ProtocolWriterFailureRecording()
		let writer = try ProtocolMessageWriter(
			handle: pipe.fileHandleForWriting,
			reportIOFailure:
			{
				recording.record($0)
			}
		)
		defer
		{
			writer.retire()
			try? pipe.fileHandleForReading.close()
			try? pipe.fileHandleForWriting.close()
		}
		let ticket = ProtocolWriteTicket(completion:
			{
				_ in recording.recordCompletion()
			})
		let first = ticket.fail(CancellationError())
		#expect(!first.requiresDisconnect)
		let failure = writer.retireAfterIOFailure(
			NSError(
				domain: NSPOSIXErrorDomain,
				code: Int(EPIPE)
			),
			ticket: ticket
		)
		#expect(failure.cause is CancellationError)
		#expect(recording.completionCount == 1)
		#expect(recording.failures.count == 1)
		#expect(recording.failures.first?.requiresDisconnect == true)
		#expect(recording.failures.first?.mayHaveBeenSent == false)
		await expectFailure(
			writer.enqueue(.object(["late": .string("never")])),
			mayHaveBeenSent: false
		)
	}

	@Test func encodingFailureSendsNoBytesAndLeavesFollowingFramesUsable() async throws
	{
		let pipe = Pipe()
		let writer = try ProtocolMessageWriter(handle: pipe.fileHandleForWriting)
		defer
		{
			writer.retire()
		}
		let reading = readToEnd(pipe.fileHandleForReading)
		await expectFailure(
			writer.enqueue(.object(["invalid": .number(NSNumber(value: Double.infinity))])),
			mayHaveBeenSent: false
		)
		await expectFailure(
			writer.enqueue(.string("invalid scalar root")),
			mayHaveBeenSent: false
		)
		try await writer.enqueue(.object(["valid": .number(7)])).wait()
		writer.retire()
		try pipe.fileHandleForWriting.close()
		#expect(try frames(in: await reading.value).map
		{
			$0["valid"] as? Int
		} == [7])
	}

	private func readToEnd(_ handle: FileHandle) -> Task<Data, Error>
	{
		Task
		{
			try await BackgroundTestWork.perform
			{
				try handle.readToEnd() ?? Data()
			}
		}
	}

	private func frames(in data: Data) throws -> [[String: Any]]
	{
		try data.split(separator: 0x0A).map
		{
			try #require(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any])
		}
	}

	private func expectFailure(
		_ ticket: ProtocolWriteTicket,
		mayHaveBeenSent: Bool
	) async
	{
		do
		{
			try await ticket.wait()
			Issue.record("The rejected protocol write unexpectedly succeeded.")
		}
		catch let failure as ProtocolWriteFailure
		{
			#expect(failure.mayHaveBeenSent == mayHaveBeenSent)
		}
		catch
		{
			Issue.record("Unexpected write failure: \(error)")
		}
	}

	private func waitUntil(_ predicate: @Sendable () -> Bool) async throws
	{
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: .seconds(3))
		while !predicate(), clock.now < deadline
		{
			try await Task.sleep(for: .milliseconds(1))
		}
		#expect(predicate())
	}
}

private final class ProtocolWriterFailureRecording: @unchecked Sendable
{
	private let lock = NSLock()
	private var storedFailures: [ProtocolWriteFailure] = []
	private var storedCompletionCount = 0

	var failures: [ProtocolWriteFailure]
	{
		lock.lock()
		defer
		{
			lock.unlock()
		}
		return storedFailures
	}

	var completionCount: Int
	{
		lock.lock()
		defer
		{
			lock.unlock()
		}
		return storedCompletionCount
	}

	func record(_ failure: ProtocolWriteFailure)
	{
		lock.lock()
		defer
		{
			lock.unlock()
		}
		storedFailures.append(failure)
	}

	func recordCompletion()
	{
		lock.lock()
		defer
		{
			lock.unlock()
		}
		storedCompletionCount += 1
	}
}
