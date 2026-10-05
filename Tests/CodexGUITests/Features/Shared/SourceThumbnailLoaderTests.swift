import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import CodexGUI

@Suite
struct SourceThumbnailLoaderTests
{
	@Test func inlinePNGUsesFeatureBoundsAndReusesDecodedThumbnails() async throws
	{
		let data = try png(
			width: 640,
			height: 320
		)
		let path = "data:image/png;base64," + data.base64EncodedString()
		let sourceData = try #require(await SourceThumbnailLoader.load(path: path))
		let source = try #require(CGImageSourceCreateWithData(
			sourceData as CFData,
			nil
		))
		let sourceImage = try #require(CGImageSourceCreateImageAtIndex(
			source,
			0,
			nil
		))
		#expect(sourceImage.width == 80 && sourceImage.height == 40)
		let transcript = try #require(await SourceThumbnailLoader.image(
			path: path,
			maximumPixelSize: 320
		))
		#expect(transcript.image.width == 320 && transcript.image.height == 160)
		let repeated = try #require(await SourceThumbnailLoader.image(
			path: path,
			maximumPixelSize: 320
		))
		#expect(repeated === transcript)
	}

	@Test func localPathsAndFileURLsReuseImagesButFileReplacementRefreshesThem() async throws
	{
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("shared-attachment-\(UUID()).png")
		defer
		{
			try? FileManager.default.removeItem(at: url)
		}
		try png(
			width: 8,
			height: 6
		).write(to: url)
		try FileManager.default.setAttributes(
			[.modificationDate: Date(timeIntervalSince1970: 1_000)],
			ofItemAtPath: url.path
		)
		let first = try #require(await SourceThumbnailLoader.image(
			path: url.path,
			maximumPixelSize: 320
		))
		let same = try #require(await SourceThumbnailLoader.image(
			path: url.absoluteString,
			maximumPixelSize: 320
		))
		#expect(first === same)
		try png(
			width: 6,
			height: 8
		).write(to: url)
		try FileManager.default.setAttributes(
			[.modificationDate: Date(timeIntervalSince1970: 2_000)],
			ofItemAtPath: url.path
		)
		let replaced = try #require(await SourceThumbnailLoader.image(
			path: url.path,
			maximumPixelSize: 320
		))
		#expect(replaced !== first)
		#expect(replaced.image.width == 6 && replaced.image.height == 8)
	}

	@Test func cancelledRequestsRejectCachedAndUncachedInlineImages() async throws
	{
		let data = try png(
			width: 7,
			height: 5
		)
		let path = "data:image/png;base64," + data.base64EncodedString()
		_ = try #require(await SourceThumbnailLoader.image(
			path: path,
			maximumPixelSize: 320
		))
		let task = Task
		{
			withUnsafeCurrentTask
			{
				$0?.cancel()
			}
			let cached = await SourceThumbnailLoader.image(
				path: path,
				maximumPixelSize: 320
			)
			let uncached = await SourceThumbnailLoader.image(
				path: path,
				maximumPixelSize: 79
			)
			let encoded = await SourceThumbnailLoader.load(data: data)
			return cached == nil && uncached == nil && encoded == nil
		}
		#expect(await task.value)
	}

	@Test func malformedRemoteAndOversizedImagesAreRejected() async
	{
		for path in [
			"data:image/png;base64,%%%",
			"data:image/png;base64," + Data("not an image".utf8).base64EncodedString(),
			"https://example.com/image.png",
			FileManager.default.temporaryDirectory.path,
		]
		{
			#expect(await SourceThumbnailLoader.image(
				path: path,
				maximumPixelSize: 320
			) == nil)
		}
		let oversized = Data(
			repeating: 0,
			count: 32 * 1024 * 1024 + 1
		)
		#expect(await SourceThumbnailLoader.load(data: oversized) == nil)
	}

	private func png(
		width: Int,
		height: Int
	) throws -> Data
	{
		let context = try #require(CGContext(
			data: nil,
			width: width,
			height: height,
			bitsPerComponent: 8,
			bytesPerRow: width * 4,
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		))
		context.setFillColor(CGColor(
			red: 0.25,
			green: 0.5,
			blue: 0.75,
			alpha: 1
		))
		context.fill(CGRect(
			x: 0,
			y: 0,
			width: width,
			height: height
		))
		let image = try #require(context.makeImage())
		let data = NSMutableData()
		let destination = try #require(CGImageDestinationCreateWithData(
			data,
			UTType.png.identifier as CFString,
			1,
			nil
		))
		CGImageDestinationAddImage(
			destination,
			image,
			nil
		)
		#expect(CGImageDestinationFinalize(destination))
		return data as Data
	}
}
