import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

enum DraftImageImportTestFixture
{
	static func image(
		width: Int = 3,
		height: Int = 2,
		bitsPerComponent: Int = 8
	) throws -> CGImage
	{
		let channelsPerPixel = 4
		let bitsPerByte = 8
		let sixteenBitToEightBitScale = UInt16.max / UInt16(UInt8.max)

		let colors: [[UInt16]] = [
			[65535, 0, 0, 65535],
			[0, 65535, 0, 65535],
			[0, 0, 65535, 65535],
			[65535, 65535, 0, 65535],
			[65535, 0, 65535, 32768],
			[0, 65535, 65535, 0],
		]
		let samples = (0 ..< width * height).flatMap
		{
			colors[$0 % colors.count]
		}
		let bytes: Data
		var bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
		if bitsPerComponent == 16
		{
			bytes = samples.withUnsafeBytes
			{
				Data($0)
			}
			bitmapInfo.insert(.byteOrder16Little)
		}
		else
		{
			bytes = Data(samples.map
			{
				UInt8($0 / sixteenBitToEightBitScale)
			})
		}

		let bitsPerPixel = bitsPerComponent * channelsPerPixel
		let bytesPerComponent = bitsPerComponent / bitsPerByte
		let bytesPerRow = width * channelsPerPixel * bytesPerComponent
		let colorSpace = try #require(CGColorSpace(name: CGColorSpace.displayP3))
		let provider = try #require(CGDataProvider(data: bytes as CFData))
		return try #require(CGImage(
			width: width,
			height: height,
			bitsPerComponent: bitsPerComponent,
			bitsPerPixel: bitsPerPixel,
			bytesPerRow: bytesPerRow,
			space: colorSpace,
			bitmapInfo: bitmapInfo,
			provider: provider,
			decode: nil,
			shouldInterpolate: false,
			intent: .defaultIntent
		))
	}

	static func encodedImage(
		_ image: CGImage,
		type: UTType = .png,
		orientation: Int = 1
	) throws -> Data
	{
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
		try #require(CGImageDestinationFinalize(destination))
		return data as Data
	}

	static func png() throws -> Data
	{
		try encodedImage(image())
	}

	static func temporaryDirectory() throws -> URL
	{
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
			"codex-image-import-\(UUID().uuidString)",
			isDirectory: true
		)
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
		return directory
	}

	static func generatedImages(in directory: URL) -> [URL]
	{
		(try? FileManager.default.contentsOfDirectory(
			at: directory,
			includingPropertiesForKeys: nil
		)) ?? []
	}
}
