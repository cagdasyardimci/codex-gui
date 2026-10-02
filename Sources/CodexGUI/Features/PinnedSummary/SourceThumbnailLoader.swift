import Foundation
import ImageIO
import UniformTypeIdentifiers

/// An actor keeps decoding off the main actor and propagates caller cancellation.
/// Bounded file reads precede decoding; generated thumbnails never exceed 80 pixels.
actor SourceThumbnailLoader
{
	private static let worker = SourceThumbnailLoader()
	private static let maximumBytes = 32 * 1024 * 1024
	private static let readChunkSize = 64 * 1024
	private static let maximumThumbnailPixelSize = 80

	static func load(path: String) async -> Data?
	{
		await worker.thumbnail(path: path)
	}

	static func load(data: Data) async -> Data?
	{
		await worker.thumbnail(data: data)
	}

	private func thumbnail(path: String) -> Data?
	{
		guard path.hasPrefix("/"), !Task.isCancelled
		else
		{
			return nil
		}
		let url = URL(fileURLWithPath: path)
		guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
				values.isRegularFile == true, let size = values.fileSize, size <= Self.maximumBytes,
				let file = try? FileHandle(forReadingFrom: url)
		else
		{
			return nil
		}
		defer
		{
			try? file.close()
		}
		var data = Data()
		while !Task.isCancelled
		{
			let chunk: Data
			do
			{
				// FileHandle returns nil at EOF; only a thrown error means the read failed.
				chunk = try file.read(upToCount: min(
					Self.readChunkSize,
					Self.maximumBytes + 1 - data.count
				)) ?? Data()
			}
			catch
			{
				return nil
			}
			if chunk.isEmpty
			{
				return thumbnail(data: data)
			}
			data.append(chunk)
			guard data.count <= Self.maximumBytes
			else
			{
				return nil
			}
		}
		return nil
	}

	private func thumbnail(data: Data) -> Data?
	{
		guard !Task.isCancelled, !data.isEmpty, data.count <= Self.maximumBytes,
				let source = CGImageSourceCreateWithData(
				data as CFData,
				[kCGImageSourceShouldCache: false] as CFDictionary
				)
		else
		{
			return nil
		}
		let options: [CFString: Any] = [
			kCGImageSourceCreateThumbnailFromImageAlways: true,
			kCGImageSourceThumbnailMaxPixelSize: Self.maximumThumbnailPixelSize,
			kCGImageSourceCreateThumbnailWithTransform: true,
			kCGImageSourceShouldCacheImmediately: false,
		]
		guard !Task.isCancelled, let image = CGImageSourceCreateThumbnailAtIndex(
			source,
			0,
			options as CFDictionary
		)
		else
		{
			return nil
		}
		return pngData(for: image)
	}

	private func pngData(for image: CGImage) -> Data?
	{
		let result = NSMutableData()
		guard let destination = CGImageDestinationCreateWithData(
			result,
			UTType.png.identifier as CFString,
			1,
			nil
		)
		else
		{
			return nil
		}
		CGImageDestinationAddImage(
			destination,
			image,
			nil
		)
		guard CGImageDestinationFinalize(destination), !Task.isCancelled
		else
		{
			return nil
		}
		return result as Data
	}
}
