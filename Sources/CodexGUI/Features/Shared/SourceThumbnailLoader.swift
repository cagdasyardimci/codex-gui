import CryptoKit
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// An actor keeps decoding off the main actor and propagates caller cancellation.
/// Sources request 80 pixels; transcript callers choose a bounded preview size.
actor SourceThumbnailLoader
{
	/// CGImage is immutable; the wrapper carries its retained pixels between actors.
	final class Thumbnail: @unchecked Sendable
	{
		let image: CGImage
		/// Full image dimensions after applying the same orientation as the decoded pixels.
		let originalPixelSize: CGSize

		init(
			image: CGImage,
			originalPixelSize: CGSize
		)
		{
			self.image = image
			self.originalPixelSize = originalPixelSize
		}
	}

	private static let worker = SourceThumbnailLoader()
	private static let maximumBytes = 32 * 1024 * 1024
	private let cache = NSCache<NSString, Thumbnail>()

	init()
	{
		cache.countLimit = 64
		cache.totalCostLimit = 16 * 1024 * 1024
	}

	static func load(path: String) async -> Data?
	{
		await worker.thumbnailData(path: path)
	}

	static func load(data: Data) async -> Data?
	{
		await worker.thumbnailData(data: data)
	}

	static func image(
		path: String,
		maximumPixelSize: Int
	) async -> Thumbnail?
	{
		await worker.thumbnailImage(
			path: path,
			maximumPixelSize: maximumPixelSize
		)
	}

	/// Decode captured bytes with the same limits and cache as path-based previews.
	static func image(
		data: Data,
		maximumPixelSize: Int
	) async -> Thumbnail?
	{
		await worker.thumbnailImage(
			data: data,
			maximumPixelSize: maximumPixelSize
		)
	}

	private func thumbnailData(path: String) -> Data?
	{
		guard let thumbnail = thumbnailImage(
			path: path,
			maximumPixelSize: 80
		)
		else
		{
			return nil
		}
		return pngData(for: thumbnail.image)
	}

	private func thumbnailData(data: Data) -> Data?
	{
		guard let thumbnail = thumbnailImage(
			data: data,
			maximumPixelSize: 80
		)
		else
		{
			return nil
		}
		return pngData(for: thumbnail.image)
	}

	private func thumbnailImage(
		path: String,
		maximumPixelSize: Int
	) -> Thumbnail?
	{
		if InlineImageData.isDataURL(path)
		{
			guard let data = InlineImageData.decode(
				path,
				maximumBytes: Self.maximumBytes
			)
			else
			{
				return nil
			}
			return thumbnailImage(
				data: data,
				maximumPixelSize: maximumPixelSize
			)
		}
		guard let url = LocalAttachmentURL.resolve(path), !Task.isCancelled,
				maximumPixelSize > 0
		else
		{
			return nil
		}
		guard let values = try? url.resourceValues(forKeys: [
			.isRegularFileKey,
			.fileSizeKey,
			.contentModificationDateKey
		]), !Task.isCancelled, values.isRegularFile == true,
		let size = values.fileSize, size <= Self.maximumBytes
		else
		{
			return nil
		}
		let key = values.contentModificationDate.map
		{
			"local:\(maximumPixelSize):\(size):\($0.timeIntervalSinceReferenceDate):\(url.path)"
				as NSString
		}
		if let key, let cached = cache.object(forKey: key)
		{
			return cached
		}
		guard let data = readFile(url), let thumbnail = decode(
			data,
			maximumPixelSize: maximumPixelSize
		)
		else
		{
			return nil
		}
		if let key
		{
			retain(
				thumbnail,
				for: key
			)
		}
		return thumbnail
	}

	private func readFile(_ url: URL) -> Data?
	{
		guard !Task.isCancelled, !url.path.utf8.contains(0)
		else
		{
			return nil
		}
		// Local previews accept symlinks; validate the opened target before reading.
		let descriptor = Darwin.open(
			url.path,
			O_RDONLY | O_NONBLOCK | O_CLOEXEC
		)
		guard descriptor >= 0
		else
		{
			return nil
		}
		defer
		{
			Darwin.close(descriptor)
		}
		return try? ContainedFileAccess.read(
			descriptor,
			maximumBytes: Self.maximumBytes
		).0
	}

	private func thumbnailImage(
		data: Data,
		maximumPixelSize: Int
	) -> Thumbnail?
	{
		guard !Task.isCancelled, !data.isEmpty, data.count <= Self.maximumBytes,
				maximumPixelSize > 0
		else
		{
			return nil
		}
		// Digest keys avoid retaining base64 payloads in the process-wide thumbnail cache.
		let digest = Data(SHA256.hash(data: data)).base64EncodedString()
		let key = "inline:\(maximumPixelSize):\(digest)" as NSString
		guard !Task.isCancelled
		else
		{
			return nil
		}
		if let cached = cache.object(forKey: key)
		{
			return cached
		}
		guard let thumbnail = decode(
			data,
			maximumPixelSize: maximumPixelSize
		)
		else
		{
			return nil
		}
		retain(
			thumbnail,
			for: key
		)
		return thumbnail
	}

	private func retain(
		_ thumbnail: Thumbnail,
		for key: NSString
	)
	{
		let cost = thumbnail.image.bytesPerRow * thumbnail.image.height + key.length * 2 + 128
		cache.setObject(
			thumbnail,
			forKey: key,
			cost: cost
		)
	}

	private func decode(
		_ data: Data,
		maximumPixelSize: Int
	) -> Thumbnail?
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
		guard let originalPixelSize = originalPixelSize(of: source)
		else
		{
			return nil
		}
		let options: [CFString: Any] = [
			kCGImageSourceCreateThumbnailFromImageAlways: true,
			kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
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
		guard !Task.isCancelled
		else
		{
			return nil
		}
		return Thumbnail(
			image: image,
			originalPixelSize: originalPixelSize
		)
	}

	private func originalPixelSize(of source: CGImageSource) -> CGSize?
	{
		guard let properties = CGImageSourceCopyPropertiesAtIndex(
			source,
			0,
			nil
		)
			as? [CFString: Any],
			let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
			let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
			width.doubleValue.isFinite, height.doubleValue.isFinite,
			width.doubleValue > 0, height.doubleValue > 0
		else
		{
			return nil
		}
		let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
		let swapsDimensions = (5 ... 8).contains(orientation)
		return CGSize(
			width: swapsDimensions ? height.doubleValue : width.doubleValue,
			height: swapsDimensions ? width.doubleValue : height.doubleValue
		)
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
