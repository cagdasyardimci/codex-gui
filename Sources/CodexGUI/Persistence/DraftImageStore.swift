import AppKit

enum DraftImageStoreError: LocalizedError
{
	case unsupported
	case tooLarge

	var errorDescription: String?
	{
		switch self
		{
		case .unsupported: "The pasted or dropped item is not a readable image."
		case .tooLarge: "The image is larger than the 20 MB attachment limit."
		}
	}
}

/// Owns only the PNG copies that the composer creates for durable draft attachments.
struct DraftImageStore
{
	private static let maximumImageBytes = 20 * 1024 * 1024

	private let directory: URL

	init(directory: URL? = nil)
	{
		self.directory =
			directory
				?? FileManager.default
				.urls(
					for: .applicationSupportDirectory,
					in: .userDomainMask
				)[0]
				.appendingPathComponent(
					"CodexGUI/DraftImages",
					isDirectory: true
				)
	}

	func importImage(
		_ image: NSImage,
		title: String = "Screenshot"
	) throws -> ComposerContextItem
	{
		let pngData = try validatedPNGData(for: image)
		let imageURL = try writeImageCopy(pngData)

		return ComposerContextItem(
			kind: .image,
			title: title,
			path: imageURL.path
		)
	}

	private func validatedPNGData(for image: NSImage) throws -> Data
	{
		guard let tiffData = image.tiffRepresentation,
				let bitmap = NSBitmapImageRep(data: tiffData),
				let pngData = bitmap.representation(
				using: .png,
				properties: [:]
				)
		else
		{
			throw DraftImageStoreError.unsupported
		}
		guard pngData.count <= Self.maximumImageBytes
		else
		{
			throw DraftImageStoreError.tooLarge
		}

		return pngData
	}

	private func writeImageCopy(_ pngData: Data) throws -> URL
	{
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
		let imageURL = directory.appendingPathComponent("\(UUID().uuidString).png")
		try pngData.write(
			to: imageURL,
			options: .atomic
		)

		return imageURL
	}

	/// Returns a normalized path only for a generated PNG inside this store.
	func ownedPath(_ path: String) -> String?
	{
		let root = directory.standardizedFileURL.resolvingSymlinksInPath().path
		let file = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
		guard file.path.hasPrefix(root + "/"),
				file.pathExtension.lowercased() == "png",
				UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil
		else
		{
			return nil
		}
		return file.path
	}

	func removeOwnedCopy(at path: String)
	{
		guard let ownedPath = ownedPath(path)
		else
		{
			return
		}
		try? FileManager.default.removeItem(atPath: ownedPath)
	}
}
