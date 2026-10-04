import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Immutable inputs captured before an image import leaves the main actor.
enum DraftImageSource: Sendable
{
	case file(URL)
	case data(Data)
	case bitmap(CGImage)

	@MainActor
	init?(image: NSImage)
	{
		guard let bitmap = image.cgImage(
			forProposedRect: nil,
			context: nil,
			hints: nil
		)
		else
		{
			return nil
		}
		self = .bitmap(bitmap)
	}

	/// Converts the primary image at its original resolution, retaining color and orientation.
	func pngData() throws -> Data
	{
		try autoreleasepool
		{
			try Task.checkCancellation()
			let data = NSMutableData()
			guard let destination = CGImageDestinationCreateWithData(
				data,
				UTType.png.identifier as CFString,
				1,
				nil
			)
			else
			{
				throw DraftImageStoreError.unsupported
			}

			try addCapturedImage(to: destination)

			try Task.checkCancellation()
			guard CGImageDestinationFinalize(destination)
			else
			{
				throw DraftImageStoreError.unsupported
			}
			try Task.checkCancellation()
			return data as Data
		}
	}

	private func addCapturedImage(to destination: CGImageDestination) throws
	{
		switch self
		{
		case let .bitmap(image):
			CGImageDestinationAddImage(
				destination,
				image,
				nil
			)
		case let .file(url):
			let source = CGImageSourceCreateWithURL(
				url as CFURL,
				nil
			)
			try addPrimaryImage(
				from: source,
				to: destination
			)
		case let .data(bytes):
			let source = CGImageSourceCreateWithData(
				bytes as CFData,
				nil
			)
			try addPrimaryImage(
				from: source,
				to: destination
			)
		}
	}

	private func addPrimaryImage(
		from source: CGImageSource?,
		to destination: CGImageDestination
	) throws
	{
		guard let source, CGImageSourceGetCount(source) > 0
		else
		{
			throw DraftImageStoreError.unsupported
		}
		try Task.checkCancellation()
		CGImageDestinationAddImageFromSource(
			destination,
			source,
			CGImageSourceGetPrimaryImageIndex(source),
			nil
		)
	}
}
