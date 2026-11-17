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
				if let description = item.fileDescription(for: path)
				{
					textParts.append(description)
				}
				contextInputs.append(
					.mention(
						name: item.mentionName(for: path),
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
				guard let path = item.path, !path.contains("\0"),
						FileManager.default.isReadableFile(atPath: path),
						let attributes = try? URL(fileURLWithPath: path).resourceValues(
						forKeys: [.isRegularFileKey]
						), attributes.isRegularFile == true
				else
				{
					throw ComposerContextError.missingImage(item.title)
				}
				contextInputs.append(.localImage(path: path))
			}
		}

		textParts += annotationDescriptions(items: items)

		let nonemptyTextParts = textParts.filter
		{
			!$0.isEmpty
		}
		let combinedText = nonemptyTextParts.joined(separator: "\n\n")
		return [.text(combinedText)] + contextInputs
	}

	static func annotationDescriptions(items: [ComposerContextItem]) -> [String]
	{
		items.filter
		{
			$0.kind == .image
		}.enumerated().compactMap
		{
			index, item in
			let annotations = (item.imageAnnotations ?? []).filter(\.isValid)
			guard !annotations.isEmpty
			else
			{
				return nil
			}
			let lines = annotations.enumerated().map
			{
				number, annotation in
				"\(number + 1). \(annotation.coordinateDescription) \(annotation.text)"
			}
			return (["Image \(index + 1):"] + lines).joined(separator: "\n")
		}
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
		guard FileManager.default.isReadableFile(atPath: file.path)
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
