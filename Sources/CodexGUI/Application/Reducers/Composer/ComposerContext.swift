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
				textParts.append(excerptDescription(
					for: item,
					path: path,
					excerpt: excerpt
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

		let combinedText = textParts.filter
		{
			!$0.isEmpty
		}.joined(separator: "\n\n")
		return [.text(combinedText)] + contextInputs
	}

	private static func validatedReferenceFile(
		for item: ComposerContextItem,
		project: URL,
		projectPath: String
	) throws -> (path: String, file: URL)
	{
		guard let path = item.path
		else
		{
			throw ComposerContextError.missingFile(item.title)
		}
		let file = project.appendingPathComponent(path).standardizedFileURL
			.resolvingSymlinksInPath()
		guard file.path.hasPrefix(projectPath + "/")
		else
		{
			throw ComposerContextError.invalidPath(path)
		}
		guard FileManager.default.fileExists(atPath: file.path)
		else
		{
			throw ComposerContextError.missingFile(path)
		}
		return (path, file)
	}

	private static func excerptDescription(
		for item: ComposerContextItem,
		path: String,
		excerpt: String
	) -> String
	{
		let firstLine = item.firstLine ?? 1
		let lastLine = item.lastLine ?? firstLine
		let numbered = excerpt.components(separatedBy: "\n").enumerated().map
		{
			"\(firstLine + $0.offset): \($0.element)"
		}.joined(separator: "\n")
		return "Selected code from \(path), lines \(firstLine)–\(lastLine):\n\(numbered)"
	}
}
