import Foundation

struct ComposerCodeFile: Sendable
{
	let relativePath: String
	let contents: String
}

/// Code selection has a smaller input budget than document viewing.
enum ComposerCodeFileReader
{
	static let maximumBytes = 500_000

	static func read(
		file: URL,
		project: URL
	) async throws -> ComposerCodeFile
	{
		let work = Task.detached
		{
			try Task.checkCancellation()
			let root = project.standardizedFileURL.resolvingSymlinksInPath()
			let selected = file.standardizedFileURL.resolvingSymlinksInPath()
			let prefix = root.path == "/" ? "/" : root.path + "/"
			guard selected.path.utf8.starts(with: prefix.utf8)
			else
			{
				throw FileViewerFailure.invalidPath
			}
			let relative = String(
				decoding: selected.path.utf8.dropFirst(prefix.utf8.count),
				as: UTF8.self
			)
			let location = FileLocation(
				root: root.path,
				relativePath: relative
			)
			let (bytes, _) = try FileSystemFileReader.read(
				at: location,
				maximumBytes: maximumBytes
			)
			guard !bytes.contains(0), let contents = String(
				data: bytes,
				encoding: .utf8
			)
			else
			{
				throw FileViewerFailure.unsupportedEncoding
			}
			try Task.checkCancellation()
			return ComposerCodeFile(
				relativePath: relative,
				contents: contents
			)
		}
		return try await withTaskCancellationHandler
		{
			try await work.value
		} onCancel:
		{
			work.cancel()
		}
	}
}
