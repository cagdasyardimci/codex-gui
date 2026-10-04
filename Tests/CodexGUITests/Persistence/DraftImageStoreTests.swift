import AppKit
import ImageIO
import Testing

@testable import CodexGUI

@Suite @MainActor
struct DraftImageStoreTests
{
	@Test func workerRetainsFullResolutionDepthColorAndAlpha() async throws
	{
		let directory = try DraftImageImportTestFixture.temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let original = try DraftImageImportTestFixture.image(
			width: 31,
			height: 17,
			bitsPerComponent: 16
		)
		let input = try DraftImageImportTestFixture.encodedImage(original)
		let store = DraftImageStore(
			directory: directory,
			preparePNG:
			{
				source in
				#expect(!Thread.isMainThread)
				return try source.pngData()
			}
		)
		let imageURL = try await store.importImage(.data(input))
		let source = try #require(CGImageSourceCreateWithURL(
			imageURL as CFURL,
			nil
		))
		let decoded = try #require(CGImageSourceCreateImageAtIndex(
			source,
			0,
			[kCGImageSourceShouldCache: false] as CFDictionary
		))
		#expect(decoded.width == original.width)
		#expect(decoded.height == original.height)
		#expect(decoded.bitsPerComponent == original.bitsPerComponent)
		#expect(decoded.colorSpace?.name == original.colorSpace?.name)
		let bitmap = NSBitmapImageRep(cgImage: decoded)
		var pixel = [UInt](
			repeating: 0,
			count: 4
		)
		bitmap.getPixel(
			&pixel,
			atX: 1,
			y: 1
		)
		// Pixel 32 is opaque blue in the fixture; the next two retain half/zero alpha.
		#expect(pixel == [0, 0, 65535, 65535])
		bitmap.getPixel(
			&pixel,
			atX: 3,
			y: 1
		)
		#expect(pixel.last == 32768)
		bitmap.getPixel(
			&pixel,
			atX: 4,
			y: 1
		)
		#expect(pixel.last == 0)
	}

	@Test(arguments: 1 ... 8)
	func conversionRetainsRenderedOrientation(_ orientation: Int) async throws
	{
		let directory = try DraftImageImportTestFixture.temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let input = try DraftImageImportTestFixture.encodedImage(
			DraftImageImportTestFixture.image(),
			type: .tiff,
			orientation: orientation
		)
		let original = try #require(NSImage(data: input))
		let tiff = try #require(original.tiffRepresentation)
		let oldBitmap = try #require(NSBitmapImageRep(data: tiff))
		let oldPNG = try #require(oldBitmap.representation(
			using: .png,
			properties: [:]
		))
		let oldImage = try #require(NSImage(data: oldPNG))
		let imageURL = try await DraftImageStore(directory: directory).importImage(.data(input))
		let imported = try #require(NSImage(contentsOf: imageURL))
		#expect(imported.size == original.size)
		#expect(try renderedPixels(imported) == renderedPixels(original))
		#expect(try renderedPixels(imported) == renderedPixels(oldImage))
	}

	@Test func limitAppliesToEncodedPNGAndAcceptsExactlyTwentyMegabytes() async throws
	{
		let directory = try DraftImageImportTestFixture.temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let maximum = 20 * 1024 * 1024
		var atLimit = try DraftImageImportTestFixture.png()
		atLimit.append(Data(
			repeating: 0,
			count: maximum - atLimit.count
		))
		let limitPNG = atLimit
		let store = DraftImageStore(
			directory: directory,
			preparePNG:
			{
				_ in limitPNG
			}
		)
		let accepted = try await store.importImage(.data(Data()))
		#expect(try Data(contentsOf: accepted).count == maximum)
		let oversized = DraftImageStore(
			directory: directory,
			preparePNG:
			{
				_ in limitPNG + Data([0])
			}
		)
		do
		{
			_ = try await oversized.importImage(.data(Data()))
			Issue.record("An encoded PNG over 20 MB was accepted.")
		}
		catch DraftImageStoreError.tooLarge
		{
		}
		let generatedPaths = DraftImageImportTestFixture.generatedImages(in: directory).map
		{
			$0.standardizedFileURL.resolvingSymlinksInPath().path
		}
		let acceptedPath = accepted.standardizedFileURL.resolvingSymlinksInPath().path
		#expect(generatedPaths == [acceptedPath])
		// A large source with a small decoded image still fits after PNG conversion.
		let reencoded = try await DraftImageStore(directory: directory).importImage(.data(limitPNG))
		#expect(try Data(contentsOf: reencoded).count < maximum)
	}

	@Test func unreadableInputAndCanceledPreparationLeaveNoGeneratedCopies() async throws
	{
		let directory = try DraftImageImportTestFixture.temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let store = DraftImageStore(directory: directory)
		do
		{
			_ = try await store.importImage(.data(Data("ordinary text".utf8)))
			Issue.record("Text was accepted as an image.")
		}
		catch DraftImageStoreError.unsupported
		{
		}

		let gate = DraftImageImportTestGate()
		defer
		{
			gate.release()
		}
		let delayed = DraftImageStore(
			directory: directory,
			preparePNG: gate.prepare
		)
		let input = try DraftImageImportTestFixture.png()
		let task = Task
		{
			try await delayed.importImage(.data(input))
		}
		let started = await gate.waitUntilStarted()
		try #require(started)
		task.cancel()
		gate.release()
		do
		{
			_ = try await task.value
			Issue.record("Canceled image preparation completed successfully.")
		}
		catch is CancellationError
		{
		}
		#expect(DraftImageImportTestFixture.generatedImages(in: directory).isEmpty)
	}

	private func renderedPixels(_ image: NSImage) throws -> Data
	{
		let bitmap = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: Int(image.size.width),
			pixelsHigh: Int(image.size.height),
			bitsPerSample: 8,
			samplesPerPixel: 4,
			hasAlpha: true,
			isPlanar: false,
			colorSpaceName: .deviceRGB,
			bytesPerRow: Int(image.size.width) * 4,
			bitsPerPixel: 0
		))
		let bytes = try #require(bitmap.bitmapData)
		bytes.initialize(
			repeating: 0,
			count: bitmap.bytesPerRow * bitmap.pixelsHigh
		)
		let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
		NSGraphicsContext.saveGraphicsState()
		defer
		{
			NSGraphicsContext.restoreGraphicsState()
		}
		NSGraphicsContext.current = context
		image.draw(in: NSRect(
			origin: .zero,
			size: image.size
		))
		return Data(
			bytes: bytes,
			count: bitmap.bytesPerRow * bitmap.pixelsHigh
		)
	}
}
