import Foundation

enum ComposerContextBuilder
{
	static func inputs(
		text: String,
		items: [ComposerContextItem],
		project: URL
	) throws -> [TurnInput]
	{
		var textParts = [text]
		var contextInputs: [TurnInput] = []
		let projectPath = project.standardizedFileURL.resolvingSymlinksInPath().path

		for item in items
		{
			switch item.kind
			{
			case .fileReference:
				let reference = try validatedReferenceFile(
					for: item,
					project: project,
					projectPath: projectPath
				)
				let path = reference.path
				textParts.append(UserMessageContextDescription.file(path: path))
				contextInputs.append(
					.mention(
						name: URL(fileURLWithPath: path).lastPathComponent,
						path: reference.file.path
					)
				)
			case .textExcerpt:
				guard let path = item.path, let excerpt = item.excerpt
				else
				{
					continue
				}
				textParts.append(UserMessageContextDescription.excerpt(
					path: path,
					text: excerpt,
					firstLine: item.firstLine,
					lastLine: item.lastLine
				))
			case .image:
				guard let path = item.path, FileManager.default.fileExists(atPath: path)
				else
				{
					throw ComposerContextError.missingImage(item.title)
				}
				textParts.append(UserMessageContextDescription.image(title: item.title))
				contextInputs.append(.localImage(path: path))
			}
		}

		let nonemptyTextParts = textParts.filter
		{
			!$0.isEmpty
		}
		let combinedText = nonemptyTextParts.joined(separator: "\n\n")
		return [.text(combinedText)] + contextInputs
	}

	private static func validatedReferenceFile(
		for item: ComposerContextItem,
		project: URL,
		projectPath: String
	) throws -> (path: String, file: URL)
	{
		guard let path = item.path, !path.contains("\0")
		else
		{
			throw ComposerContextError.missingFile(item.title)
		}
		let candidate = NSString(string: path).isAbsolutePath
			? URL(fileURLWithPath: path) : project.appendingPathComponent(path)
		let file = candidate.standardizedFileURL.resolvingSymlinksInPath()
		let prefix = projectPath == "/" ? "/" : projectPath + "/"
		guard file.path.utf8.starts(with: prefix.utf8), file.path != projectPath
		else
		{
			throw ComposerContextError.invalidPath(path)
		}
		guard FileManager.default.fileExists(atPath: file.path)
		else
		{
			throw ComposerContextError.missingFile(path)
		}
		let relative = String(
			decoding: file.path.utf8.dropFirst(prefix.utf8.count),
			as: UTF8.self
		)
		return (relative, file)
	}
}
