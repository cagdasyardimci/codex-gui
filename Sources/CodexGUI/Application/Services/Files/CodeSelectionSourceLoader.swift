import Foundation

/// Loads the explicitly selected code source off the main actor within the captured checkout.
enum CodeSelectionSourceLoader
{
	struct Source: Sendable
	{
		let relativePath: String
		let contents: String
	}

	enum Failure: LocalizedError
	{
		case outsideProject, unsupportedSource

		var errorDescription: String?
		{
			switch self
			{
			case .outsideProject: "Choose a file inside the current project."
			case .unsupportedSource: "Choose a UTF-8 text file under 500 KB."
			}
		}
	}

	static func load(
		projectPath: String,
		file: URL
	) async throws -> Source
	{
		try Task.checkCancellation()
		let worker = Task.detached(priority: .userInitiated)
		{
			try Task.checkCancellation()
			let project = URL(fileURLWithPath: projectPath).standardizedFileURL
				.resolvingSymlinksInPath()
			let selected = file.standardizedFileURL.resolvingSymlinksInPath()
			let prefix = project.path.hasSuffix("/") ? project.path : project.path + "/"
			guard selected.path.hasPrefix(prefix)
			else
			{
				throw Failure.outsideProject
			}
			let relative = String(selected.path.dropFirst(prefix.count))
			let location = FileLocation(
				root: project.path,
				relativePath: relative
			)
			let data: Data
			do
			{
				(data, _) = try ContainedFileAccess.read(
					location,
					maximumBytes: 500_000
				)
			}
			catch FileViewerFailure.tooLarge
			{
				throw Failure.unsupportedSource
			}
			guard let contents = String(
				data: data,
				encoding: .utf8
			)
			else
			{
				throw Failure.unsupportedSource
			}
			try Task.checkCancellation()
			return Source(
				relativePath: relative,
				contents: contents
			)
		}
		return try await withTaskCancellationHandler
		{
			try await worker.value
		}
		onCancel:
		{
			worker.cancel()
		}
	}
}
