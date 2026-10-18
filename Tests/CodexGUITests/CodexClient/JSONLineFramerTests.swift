import Foundation
import Testing

@testable import CodexGUI

struct JSONLineFramerTests
{
	@Test func largeFragmentedMessagePreservesAdjacentFramesAndPartialRemainder() throws
	{
		let text = String(
			repeating: "a",
			count: 4 * 1024 * 1024
		) + "\u{2028}終"
		let frame = try JSONSerialization.data(withJSONObject: ["text": text])
		let framer = JSONLineFramer()
		for start in stride(
			from: 0,
			to: frame.count,
			by: 4096
		)
		{
			#expect(framer.append(frame.subdata(in: start ..< min(
				start + 4096,
				frame.count
			)))
			.isEmpty)
		}
		let adjacent = Data("{\"id\":2}".utf8)
		#expect(framer.append(Data("\n\n{\"id\":2}\n{\"id\":".utf8)) == [frame, adjacent])
		#expect(framer.append(Data()).isEmpty)
		#expect(framer.append(Data("3}\n".utf8)) == [Data("{\"id\":3}".utf8)])
	}

	@Test func byteFragmentsKeepUnicodeSeparatorsInsideJSONStrings() throws
	{
		let frames = [
			Data("{\"text\":\"A\u{2028}B\u{2029}C雪\"}".utf8),
			Data("{\"text\":\"next\"}\r".utf8),
		]
		var stream = Data([0x0A])
		for frame in frames
		{
			stream.append(frame)
			stream.append(0x0A)
		}
		let framer = JSONLineFramer()
		var received: [Data] = []
		for byte in stream
		{
			received.append(contentsOf: framer.append(Data([byte])))
		}
		#expect(received == frames)
		let decoded = try JSONSerialization.jsonObject(with: received[0]) as? [String: String]
		#expect(decoded?["text"] == "A\u{2028}B\u{2029}C雪")
	}

	@Test func variedReadBoundariesProduceTheSameCompleteFrames()
	{
		let frames = (0 ..< 120).map
		{
			Data("{\"id\":\($0),\"text\":\"\(String(repeating: "x", count: $0 % 19))\"}".utf8)
		}
		var stream = Data()
		for frame in frames
		{
			stream.append(frame)
			stream.append(contentsOf: [0x0A, 0x0A])
		}
		for chunkSize in [1, 2, 7, 31, 128, 4096]
		{
			let framer = JSONLineFramer()
			var received: [Data] = []
			for start in stride(
				from: 0,
				to: stream.count,
				by: chunkSize
			)
			{
				received.append(contentsOf: framer.append(stream.subdata(
					in: start ..< min(
						start + chunkSize,
						stream.count
					)
				)))
			}
			#expect(received == frames)
		}
	}

	@Test func jsonLineFramerPreservesFragmentedAndAdjacentMessages()
	{
		let framer = JSONLineFramer()

		#expect(framer.append(Data("{\"id\":1".utf8)) == [])
		#expect(
			framer.append(Data("}\n{\"id\":2}\n{\"id\":3".utf8))
				== [Data("{\"id\":1}".utf8), Data("{\"id\":2}".utf8)]
		)
		#expect(framer.append(Data("}\n".utf8)) == [Data("{\"id\":3}".utf8)])
	}

	@Test func retainedFramesSurviveLaterPartialAndCompleteReads()
	{
		let framer = JSONLineFramer()
		let first = Data(String(
			repeating: "a",
			count: 1024 * 1024
		).utf8)
		#expect(framer.append(first).isEmpty)
		let retained = framer.append(Data("\nsecond\nthi".utf8))
		#expect(retained == [first, Data("second".utf8)])
		#expect(framer.append(Data("rd\nfourth\nfif".utf8)) == [
			Data("third".utf8),
			Data("fourth".utf8),
		])
		#expect(framer.append(Data("th\n".utf8)) == [Data("fifth".utf8)])
		#expect(retained == [first, Data("second".utf8)])
	}

	@Test func slicedReadsPreserveNonzeroIndicesAndPartialRemainders()
	{
		let framer = JSONLineFramer()
		let first = Data("discard\nfirst\nsec".utf8).dropFirst(8)
		let second = Data("discardond\n\nthird\n".utf8).dropFirst(7)
		#expect(first.startIndex > 0)
		#expect(second.startIndex > 0)
		#expect(framer.append(first) == [Data("first".utf8)])
		#expect(framer.append(second) == [Data("second".utf8), Data("third".utf8)])
	}

}
