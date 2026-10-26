import Foundation
import Testing

@testable import CodexGUI

@Suite
struct InlineImageDataTests
{
	@Test func inlineImagePayloadsPreserveTheirBytes()
	{
		let bytes = Data([0, 1, 2, 253, 254, 255])
		let value = "DATA:IMAGE/PNG;BASE64," + bytes.base64EncodedString()
		#expect(InlineImageData.isDataURL(value))
		#expect(InlineImageData.decode(
			value,
			maximumBytes: bytes.count
		) == bytes)
	}

	@Test func invalidOrNonImagePayloadsAreRejected()
	{
		for value in [
			"data:image/png;base64,%%%",
			"data:image/png;base64",
			"data:image/png,encoded",
			"data:text/plain;base64,YQ==",
			"https://example.com/image.png",
			"file:///tmp/image.png",
		]
		{
			#expect(InlineImageData.decode(
				value,
				maximumBytes: 32
			) == nil)
		}
	}

	@Test func decodedAndEncodedPayloadBoundsAreBothEnforced()
	{
		let value = "data:image/png;base64," + Data([1, 2, 3, 4]).base64EncodedString()
		#expect(InlineImageData.decode(
			value,
			maximumBytes: 3
		) == nil)
		#expect(InlineImageData.decode(
			value,
			maximumBytes: 0
		) == nil)
		let oversized = "data:image/png;" + String(
			repeating: "x",
			count: 2_000
		) + ";base64,YQ=="
		#expect(InlineImageData.decode(
			oversized,
			maximumBytes: 1
		) == nil)
		#expect(InlineImageData.decode(
			value,
			maximumBytes: Int.max
		) == nil)
	}

	@Test func cancelledCallersDoNotDecodePayloads() async
	{
		let task = Task
		{
			withUnsafeCurrentTask
			{
				$0?.cancel()
			}
			return InlineImageData.decode(
				"data:image/png;base64,YQ==",
				maximumBytes: 1
			)
		}
		#expect(await task.value == nil)
	}
}
