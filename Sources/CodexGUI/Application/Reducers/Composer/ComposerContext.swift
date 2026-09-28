import Foundation

enum ComposerContextKind: String, Codable
{
	case fileReference
	case textExcerpt
	case image

	var title: String
	{
		switch self
		{
		case .fileReference: "File reference"
		case .textExcerpt: "Code excerpt"
		case .image: "Image"
		}
	}
}

/// User-supplied context is kept with the draft until the server acknowledges a turn.
struct ComposerContextItem: Codable, Equatable, Identifiable
{
	let id: String
	let kind: ComposerContextKind
	let title: String
	let path: String?
	let firstLine: Int?
	let lastLine: Int?
	let excerpt: String?

	init(
		id: String = UUID().uuidString,
		kind: ComposerContextKind,
		title: String,
		path: String? = nil,
		firstLine: Int? = nil,
		lastLine: Int? = nil,
		excerpt: String? = nil
	)
	{
		self.id = id
		self.kind = kind
		self.title = title
		self.path = path
		self.firstLine = firstLine
		self.lastLine = lastLine
		self.excerpt = excerpt
	}

	func reused() -> ComposerContextItem
	{
		ComposerContextItem(
			kind: kind,
			title: title,
			path: path,
			firstLine: firstLine,
			lastLine: lastLine,
			excerpt: excerpt
		)
	}

	var detail: String
	{
		switch kind
		{
		case .fileReference:
			return path ?? "Missing path"
		case .textExcerpt:
			let lines = firstLine.map
			{
				"lines \($0)–\(lastLine ?? $0)"
			} ?? "selected text"
			return "\(path ?? "Unknown file") · \(lines)"
		case .image:
			return path.map
			{
				URL(fileURLWithPath: $0).lastPathComponent
			} ?? "Missing image"
		}
	}
}

enum TurnInput: Equatable
{
	case text(String)
	case mention(
		name: String,
		path: String
	)
	case localImage(path: String)

	var protocolValue: [String: Any]
	{
		switch self
		{
		case .text(let text):
			["type": "text", "text": text, "text_elements": []]
		case .mention(
			let name,
			let path
		):
			["type": "mention", "name": name, "path": path]
		case .localImage(let path):
			["type": "localImage", "path": path]
		}
	}
}

enum ComposerContextError: LocalizedError
{
	case missingFile(String)
	case missingImage(String)
	case invalidPath(String)

	var errorDescription: String?
	{
		switch self
		{
		case .missingFile(let path): "Referenced file is unavailable: \(path)"
		case .missingImage(let path): "Attached image is unavailable: \(path)"
		case .invalidPath(let path): "Reference is outside this project: \(path)"
		}
	}
}

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

enum CodeRangeSelection
{
	static func item(
		path: String,
		contents: String,
		selectedRange: NSRange
	) -> ComposerContextItem?
	{
		let text = contents as NSString
		guard selectedRange.length > 0, selectedRange.location != NSNotFound,
				NSMaxRange(selectedRange) <= text.length
		else
		{
			return nil
		}

		let excerptStart = text.lineRange(for: NSRange(
			location: selectedRange.location,
			length: 0
		))
		.location
		let lastSelectedLocation = max(
			selectedRange.location,
			NSMaxRange(selectedRange) - 1
		)
		let lastSelectedLineRange = text.lineRange(for: NSRange(
			location: lastSelectedLocation,
			length: 0
		))
		let excerptEnd = NSMaxRange(lastSelectedLineRange)

		let firstLine = text.substring(to: excerptStart).filter
		{
			$0 == "\n"
		}.count + 1
		let precedingNewlineCount = text.substring(to: excerptEnd).filter
		{
			$0 == "\n"
		}.count
		// A final line without a newline still counts as a line in the selection.
		let includesUnterminatedFinalLine =
			excerptEnd == text.length && !contents.hasSuffix("\n")
		let lastLine = precedingNewlineCount + (includesUnterminatedFinalLine ? 1 : 0)

		let excerpt = text.substring(with: NSRange(
			location: excerptStart,
			length: excerptEnd - excerptStart
		))
		.trimmingCharacters(in: .newlines)
		guard !excerpt.isEmpty, excerpt.utf8.count <= 30_000
		else
		{
			return nil
		}
		return ComposerContextItem(
			kind: .textExcerpt,
			title: URL(fileURLWithPath: path).lastPathComponent,
			path: path,
			firstLine: firstLine,
			lastLine: max(
				firstLine,
				lastLine
			),
			excerpt: excerpt
		)
	}
}
