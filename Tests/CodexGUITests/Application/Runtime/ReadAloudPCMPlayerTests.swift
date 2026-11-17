import Foundation
import Testing

@testable import CodexGUI

struct ReadAloudPCMPlayerTests
{
	@Test func pcmDecodingPreservesLittleEndianSignedStereoSamples() throws
	{
		let bytes = Data([0x00, 0x80, 0xFF, 0x7F, 0x00, 0x00, 0x00, 0x40])
		let chunk = try ReadAloudAudioChunk(
			base64Data: bytes.base64EncodedString(),
			sampleRate: 48000,
			numChannels: 2,
			samplesPerChannel: 2
		)
		#expect(chunk.frameCount == 2)
		#expect(chunk.sampleRate == 48000)
		#expect(chunk.channelCount == 2)
		#expect(chunk.normalizedInterleavedSamples() == [-1, Float(32767) / 32768, 0, 0.5])
	}

	@Test func malformedAudioAndContradictoryMetadataAreRejected() throws
	{
		#expect(throws: ReadAloudPCMError.invalidEncoding)
		{
			try ReadAloudAudioChunk(
				base64Data: "invalid!",
				sampleRate: 24000,
				numChannels: 1
			)
		}
		for (data, rate, channels, count, error) in [
			(Data(), 24000, 1, nil, ReadAloudPCMError.emptyAudio),
			(Data([0, 0]), 0, 1, nil, .invalidFormat),
			(Data([0, 0]), 24000, 0, nil, .invalidFormat),
			(Data([0, 0, 0]), 24000, 1, nil, .sampleCountMismatch),
			(Data([0, 0]), 24000, 2, nil, .sampleCountMismatch),
			(Data([0, 0]), 24000, 1, 2, .sampleCountMismatch),
			(
				Data(
					repeating: 0,
					count: ReadAloudAudioChunk.maximumPacketBytes + 2
				),
				24000,
				1,
				nil,
				.packetTooLarge
			),
		] as [(Data, Int, Int, Int?, ReadAloudPCMError)]
		{
			#expect(throws: error)
			{
				try ReadAloudAudioChunk(
					pcmData: data,
					sampleRate: rate,
					numChannels: channels,
					samplesPerChannel: count
				)
			}
		}
	}

	@Test func drainWaitsForEveryScheduledBufferAndIsDeliveredOnce() throws
	{
		var queue = ReadAloudPlaybackQueue(maximumBytes: 24)
		let first = try queue.enqueue(byteCount: 8)
		let last = try queue.enqueue(byteCount: 16)
		let finishedBeforePlayback = queue.finish()
		#expect(!finishedBeforePlayback)
		#expect(throws: ReadAloudPCMError.segmentNotDrained)
		{
			try queue.enqueue(byteCount: 1)
		}
		let drainedAfterLast = queue.complete(last)
		#expect(!drainedAfterLast)
		#expect(queue.queuedBytes == 8)
		let drainedAfterFirst = queue.complete(first)
		#expect(drainedAfterFirst)
		#expect(queue.queuedBytes == 0)
		let duplicateCompletion = queue.complete(first)
		#expect(!duplicateCompletion)
		let duplicateFinish = queue.finish()
		#expect(!duplicateFinish)
		let nextSegment = try queue.enqueue(byteCount: 12)
		let nextFinishedBeforePlayback = queue.finish()
		#expect(!nextFinishedBeforePlayback)
		let nextDrained = queue.complete(nextSegment)
		#expect(nextDrained)
	}

	@Test func cancellationRejectsLateCompletionAndBudgetRecoversAsAudioPlays() throws
	{
		var queue = ReadAloudPlaybackQueue(maximumBytes: 16)
		let retired = try queue.enqueue(byteCount: 16)
		#expect(throws: ReadAloudPCMError.queueFull)
		{
			try queue.enqueue(byteCount: 1)
		}
		queue.reset()
		let current = try queue.enqueue(byteCount: 16)
		let finishedBeforePlayback = queue.finish()
		#expect(!finishedBeforePlayback)
		let retiredCompletion = queue.complete(retired)
		#expect(!retiredCompletion)
		#expect(queue.queuedBytes == 16)
		let currentCompletion = queue.complete(current)
		#expect(currentCompletion)
		let buffer = try queue.enqueue(byteCount: 8)
		let bufferCompletion = queue.complete(buffer)
		#expect(!bufferCompletion)
		#expect(queue.queuedBytes == 0)
		_ = try queue.enqueue(byteCount: 16)
	}
}
