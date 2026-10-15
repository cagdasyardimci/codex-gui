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
		let data = try imageData(
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
		#expect(transcript.originalPixelSize == CGSize(
			width: 640,
			height: 320
		))
		let repeated = try #require(await SourceThumbnailLoader.image(
			path: path,
			maximumPixelSize: 320
		))
		#expect(repeated === transcript)
	}

	@Test(arguments: 1 ... 8)
	func originalDimensionsMatchTransformedThumbnailOrientation(_ orientation: Int) async throws
	{
		let data = try imageData(
			width: 640,
			height: 320,
			type: .jpeg,
			orientation: orientation,
			quadrants: true
		)
		let path = "data:image/jpeg;base64," + data.base64EncodedString()
		let thumbnail = try #require(await SourceThumbnailLoader.image(
			path: path,
			maximumPixelSize: 80
		))
		let swapsDimensions = (5 ... 8).contains(orientation)
		#expect(thumbnail.originalPixelSize == CGSize(
			width: swapsDimensions ? 320 : 640,
			height: swapsDimensions ? 640 : 320
		))
		#expect(thumbnail.image.width == (swapsDimensions ? 40 : 80))
		#expect(thumbnail.image.height == (swapsDimensions ? 80 : 40))
		let red = [1.0, 0, 0]
		let green = [0.0, 1, 0]
		let blue = [0.0, 0, 1]
		let yellow = [1.0, 1, 0]
		// EXIF specifies these corner permutations, in top-left, top-right,
		// bottom-left, bottom-right order; no production transform computes this oracle.
		let expectedCorners = [
			[red, green, blue, yellow],
			[green, red, yellow, blue],
			[yellow, blue, green, red],
			[blue, yellow, red, green],
			[red, blue, green, yellow],
			[blue, red, yellow, green],
			[yellow, green, blue, red],
			[green, yellow, red, blue],
		]
		try expectCorners(
			in: thumbnail.image,
			matching: expectedCorners[orientation - 1]
		)
	}

	@Test func localPathsAndFileURLsReuseImagesButFileReplacementRefreshesThem() async throws
	{
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("shared-attachment-\(UUID()).png")
		defer
		{
			try? FileManager.default.removeItem(at: url)
		}
		try imageData(
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
		#expect(first.originalPixelSize == CGSize(
			width: 8,
			height: 6
		))
		try imageData(
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
		#expect(replaced.originalPixelSize == CGSize(
			width: 6,
			height: 8
		))
	}

	@Test func cancelledRequestsRejectCachedAndUncachedInlineImages() async throws
	{
		let data = try imageData(
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

	@Test func malformedRemoteAndOversizedImagesAreRejected() async throws
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
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("bounded-thumbnail-\(UUID()).png")
		defer
		{
			try? FileManager.default.removeItem(at: url)
		}
		let png = try imageData(
			width: 8,
			height: 6
		)
		for byteCount in [32 * 1024 * 1024, 32 * 1024 * 1024 + 1]
		{
			let bytes = png + Data(
				repeating: 0,
				count: byteCount - png.count
			)
			// Trailing bytes preserve this PNG's validity, so rejection must come from
			// the loader's byte limit rather than the image decoder.
			let source = try #require(CGImageSourceCreateWithData(
				bytes as CFData,
				nil
			))
			let decoded = try #require(CGImageSourceCreateImageAtIndex(
				source,
				0,
				nil
			))
			#expect(decoded.width == 8 && decoded.height == 6)
			#expect(bytes.count == byteCount)
			try bytes.write(to: url)
			let encoded = await SourceThumbnailLoader.load(data: bytes)
			let local = await SourceThumbnailLoader.image(
				path: url.path,
				maximumPixelSize: 320
			)
			if byteCount == 32 * 1024 * 1024
			{
				let encodedData = try #require(encoded)
				let encodedSource = try #require(CGImageSourceCreateWithData(
					encodedData as CFData,
					nil
				))
				let result = try #require(CGImageSourceCreateImageAtIndex(
					encodedSource,
					0,
					nil
				))
				#expect(result.width == 8 && result.height == 6)
				#expect(local?.image.width == 8 && local?.image.height == 6)
				#expect(local?.originalPixelSize == CGSize(
					width: 8,
					height: 6
				))
			}
			else
			{
				#expect(encoded == nil)
				#expect(local == nil)
			}
		}
	}

	private func expectCorners(
		in image: CGImage,
		matching expected: [[Double]]
	) throws
	{
		let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
		for (index, coordinate) in [
			(image.width / 4, image.height / 4),
			(image.width * 3 / 4, image.height / 4),
			(image.width / 4, image.height * 3 / 4),
			(image.width * 3 / 4, image.height * 3 / 4),
		].enumerated()
		{
			let pixel = try #require(image.cropping(to: CGRect(
				x: coordinate.0,
				y: coordinate.1,
				width: 1,
				height: 1
			)))
			let context = try #require(CGContext(
				data: nil,
				width: 1,
				height: 1,
				bitsPerComponent: 8,
				bytesPerRow: 4,
				space: colorSpace,
				bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
			))
			context.draw(
				pixel,
				in: CGRect(
					x: 0,
					y: 0,
					width: 1,
					height: 1
				)
			)
			let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
			for channel in 0 ..< 3
			{
				#expect(abs(Double(bytes[channel]) / 255 - expected[index][channel]) < 0.15)
			}
		}
	}

	private func imageData(
		width: Int,
		height: Int,
		type: UTType = .png,
		orientation: Int = 1,
		quadrants: Bool = false
	) throws -> Data
	{
		let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
		let context = try #require(CGContext(
			data: nil,
			width: width,
			height: height,
			bitsPerComponent: 8,
			bytesPerRow: width * 4,
			space: colorSpace,
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
		if quadrants
		{
			let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
			let colors: [[UInt8]] = [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 0]]
			for y in 0 ..< height
			{
				for x in 0 ..< width
				{
					let color = colors[(y < height / 2 ? 0 : 2) + (x < width / 2 ? 0 : 1)]
					let offset = (y * width + x) * 4
					for channel in 0 ..< 3
					{
						pixels[offset + channel] = color[channel]
					}
					pixels[offset + 3] = 255
				}
			}
		}
		let image = try #require(context.makeImage())
		let data = NSMutableData()
		let destination = try #require(CGImageDestinationCreateWithData(
			data,
			type.identifier as CFString,
			1,
			nil
		))
		CGImageDestinationAddImage(
			destination,
			image,
			[kCGImagePropertyOrientation: orientation] as CFDictionary
		)
		#expect(CGImageDestinationFinalize(destination))
		return data as Data
	}
}
