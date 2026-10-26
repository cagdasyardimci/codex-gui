import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import CodexGUI

@Suite
struct SourceThumbnailLoaderTests
{

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
