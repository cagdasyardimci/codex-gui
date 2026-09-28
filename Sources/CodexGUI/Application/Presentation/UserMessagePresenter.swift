import Foundation

/// Descriptions included in outgoing text remain part of the model's context.
enum UserMessageContextDescription
{
	static let filePrefix = "File reference: "
	static let imagePrefix = "Attached image: "

	static func file(path: String) -> String
	{
		filePrefix + path
	}
	static func image(title: String) -> String
	{
		imagePrefix + title
	}
}

/// Uses the same text and attachment presentation before acknowledgment and after history loads.
enum UserMessagePresenter
{
	private struct Reference
	{
		let kind: UserMessageReference.Kind
		let name: String
		let path: String
	}

	static func body(for item: CodexItem) -> String
	{
		let references = item.references.map
		{
			Reference(
				kind: $0.kind,
				name: $0.name,
				path: $0.path
			)
		}

		return render(
			text: item.text ?? "",
			references: references
		)
	}

	static func body(for inputs: [TurnInput]) -> String
	{
		var textParts: [String] = []
		var references: [Reference] = []

		for input in inputs
		{
			switch input
			{
			case .text(let value):
				textParts.append(value)
			case .mention(
				let name,
				let path
			):
				references.append(Reference(
					kind: .fileReference,
					name: name,
					path: path
				))
			case .localImage(let path):
				references.append(
					Reference(
						kind: .image,
						name: URL(fileURLWithPath: path).lastPathComponent,
						path: path
					)
				)
			}
		}

		return render(
			text: textParts.joined(separator: "\n"),
			references: references
		)
	}

	private static func render(
		text: String,
		references: [Reference]
	) -> String
	{
		let lines = text.components(separatedBy: "\n")
		var describedImages = lines.filter
		{
			$0.hasPrefix(UserMessageContextDescription.imagePrefix)
		}.count
		var labels: [String] = []

		for reference in references
		{
			switch reference.kind
			{
			case .fileReference:
				let isDescribed = containsFileDescription(
					for: reference,
					in: lines
				)
				if !isDescribed
				{
					labels.append("[File reference: \(reference.name)]")
				}
			case .image:
				// The outgoing description retains the user-facing title; the wire image has only a
				// path.
				if describedImages > 0
				{
					describedImages -= 1
				}
				else
				{
					labels.append("[Image: \(reference.name)]")
				}
			}
		}

		let visibleParts = ([text] + labels).filter
		{
			!$0.isEmpty
		}
		return visibleParts.joined(separator: "\n")
	}

	private static func containsFileDescription(
		for reference: Reference,
		in lines: [String]
	) -> Bool
	{
		return lines.contains
		{
			line in
			guard line.hasPrefix(UserMessageContextDescription.filePrefix)
			else
			{
				return false
			}

			let describedPath = String(
				line.dropFirst(UserMessageContextDescription.filePrefix.count)
			)

			guard !describedPath.isEmpty
			else
			{
				return false
			}

			let matchesExactPath = reference.path == describedPath
			if matchesExactPath
			{
				return true
			}

			let matchesPathSuffix = reference.path.hasSuffix("/" + describedPath)
			if matchesPathSuffix
			{
				return true
			}

			// File mentions retain the chosen name even when their path resolves a symbolic
			// link.
			let describedFileName = URL(fileURLWithPath: describedPath).lastPathComponent
			let matchesFileName = describedFileName == reference.name

			return matchesFileName
		}
	}
}
