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
struct DraftImageStore: Sendable
{
	private static let maximumImageBytes = 20 * 1024 * 1024

	private let directory: URL
	private let preparePNG: @Sendable (DraftImageSource) throws -> Data

	init(
		directory: URL? = nil,
		preparePNG: @escaping @Sendable (DraftImageSource) throws -> Data =
		{
			try $0.pngData()
		}
	)
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
		self.preparePNG = preparePNG
	}

	/// Compatibility for callers that already own an AppKit image. Live imports use snapshots.
	@MainActor
	func importImage(
		_ image: NSImage,
		title: String = "Screenshot"
	) throws -> ComposerContextItem
	{
		guard let source = DraftImageSource(image: image)
		else
		{
			throw DraftImageStoreError.unsupported
		}
		let imageURL = try importImageCopy(source)

		return ComposerContextItem(
			kind: .image,
			title: title,
			path: imageURL.path
		)
	}

	func importImage(_ source: DraftImageSource) async throws -> URL
	{
		let worker = Task.detached(priority: .userInitiated)
		{
			try importImageCopy(source)
		}
		return try await withTaskCancellationHandler
		{
			let imageURL = try await worker.value
			do
			{
				try Task.checkCancellation()
				return imageURL
			}
			catch
			{
				await discardImportedCopy(imageURL)
				throw error
			}
		}
		onCancel:
		{
			worker.cancel()
		}
	}

	private func importImageCopy(_ source: DraftImageSource) throws -> URL
	{
		try Task.checkCancellation()
		let pngData = try preparePNG(source)
		try Task.checkCancellation()
		guard pngData.count <= Self.maximumImageBytes
		else
		{
			throw DraftImageStoreError.tooLarge
		}

		return try writeImageCopy(pngData)
	}

	private func writeImageCopy(_ pngData: Data) throws -> URL
	{
		try Task.checkCancellation()
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
		let imageURL = directory.appendingPathComponent("\(UUID().uuidString).png")
		do
		{
			try Task.checkCancellation()
			try pngData.write(
				to: imageURL,
				options: .atomic
			)
			try Task.checkCancellation()
		}
		catch
		{
			try? FileManager.default.removeItem(at: imageURL)
			throw error
		}

		return imageURL
	}

	func discardImportedCopy(_ imageURL: URL) async
	{
		await Task.detached(priority: .utility)
		{
			removeOwnedCopy(at: imageURL.path)
		}.value
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
