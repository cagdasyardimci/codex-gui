import Foundation

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
