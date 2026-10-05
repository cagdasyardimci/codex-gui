import Foundation

/// Composes a turn's reported patches without reading the current working tree.
enum ConversationNetFileChanges
{
	private static let maximumMaterializedLines = 8_192
	private static let maximumDifferenceProduct = 1_000_000
	private static let maximumCompositionBytes = 2 * 1_024 * 1_024
	private static let maximumHunkApplications = 256

	static func merge(_ changes: [FileChange]) -> [FileChange]
	{
		var groups: [[FileChange]] = []
		var indices: [Data: Int] = [:]
		for change in changes
		{
			let path = Data(change.path.utf8)
			let index: Int
			if let existing = indices[path]
			{
				index = existing
				groups[index].append(change)
			}
			else
			{
				index = groups.count
				groups.append([change])
			}
			indices[path] = index
			if let destination = change.movePath
			{
				let destinationPath = Data(destination.utf8)
				if destinationPath != path
				{
					// A later edit of the vacated path belongs to a different file.
					indices.removeValue(forKey: path)
				}
				indices[destinationPath] = index
			}
		}
		return groups.compactMap(netChange)
	}

	private static func netChange(_ changes: [FileChange]) -> FileChange?
	{
		guard let first = changes.first, let last = changes.last
		else
		{
			return nil
		}
		var composition = Composition(created: first.kind == "add")
		var composed = changes.reduce(0)
		{
			min(
				maximumCompositionBytes + 1,
				$0 + min(
					maximumCompositionBytes + 1,
					$1.diff.utf8.count
				)
			)
		} <= maximumCompositionBytes
		for change in changes where composed
		{
			if !composition.apply(change)
			{
				composed = false
				break
			}
		}
		let destination = changes.compactMap(\.movePath).last ?? last.path
		let renamed = !destination.utf8.elementsEqual(first.path.utf8)
		let kind = last.kind == "delete" ? "delete" : first.kind == "add" ? "add" : "update"
		let diff: String
		if composed, let composedDiff = composition.diff()
		{
			diff = composedDiff
			guard !diff.isEmpty || renamed || (first.kind == "add" && last.kind != "delete")
				|| (first.kind != "add" && last.kind == "delete")
			else
			{
				return nil
			}
		}
		else
		{
			// Incomplete, incompatible or expensive history retains every reported edit.
			diff = changes.map(normalizedDiff).joined(separator: "\n")
		}
		var metadata: [String: Any] = ["type": kind]
		if renamed
		{
			metadata["move_path"] = destination
		}
		return FileChange(json: ["path": first.path, "kind": metadata, "diff": diff])
	}

	private static func contentLines(_ text: String) -> [String]
	{
		guard !text.isEmpty
		else
		{
			return []
		}
		var lines = text.components(separatedBy: "\n")
		if lines.last == ""
		{
			lines.removeLast()
		}
		return lines
	}

	private static func normalizedDiff(_ change: FileChange) -> String
	{
		guard (change.kind == "add" || change.kind == "delete"),
				!change.diff.hasPrefix("@@ "), !change.diff.contains("\n@@ ")
		else
		{
			return change.diff
		}
		let lines = contentLines(change.diff)
		guard !lines.isEmpty
		else
		{
			return ""
		}
		let added = change.kind == "add"
		let header = added ? "@@ -0,0 +1,\(lines.count) @@" : "@@ -1,\(lines.count) +0,0 @@"
		return ([header] + lines.map
		{
			(added ? "+" : "-") + $0
		}).joined(separator: "\n")
	}

	private struct Line
	{
		let origin: Int?
		var text: String?
	}

	private enum Token: Equatable
	{
		case text(String)
		case unknown(Int)

		static func == (lhs: Self, rhs: Self) -> Bool
		{
			switch (lhs, rhs)
			{
			case (.text(let lhs), .text(let rhs)): lhs.utf8.elementsEqual(rhs.utf8)
			case (.unknown(let lhs), .unknown(let rhs)): lhs == rhs
			default: false
			}
		}
	}

	private struct Composition
	{
		let created: Bool
		var original: [String?] = []
		var current: [Line] = []
		var hunkApplications = 0

		mutating func extend(to count: Int) -> Bool
		{
			let additionalLines = max(
				0,
				count - current.count
			)
			guard count <= maximumMaterializedLines,
					original.count <= maximumMaterializedLines - additionalLines,
					!created || count <= current.count
			else
			{
				return false
			}
			while current.count < count
			{
				current.append(Line(
					origin: original.count,
					text: nil
				))
				original.append(nil)
			}
			return true
		}

		mutating func apply(_ change: FileChange) -> Bool
		{
			// Line-only history cannot safely compose a change in the final newline.
			guard !change.diff.contains("\\ No newline at end of file")
			else
			{
				return false
			}
			let hunks = GitDiffParser.hunks(in: normalizedDiff(change))
			guard !hunks.isEmpty
			else
			{
				return change.diff.isEmpty && (change.kind != "update" || change.movePath != nil)
			}
			var offset = 0
			for hunk in hunks
			{
				hunkApplications += 1
				guard hunkApplications <= maximumHunkApplications
				else
				{
					return false
				}
				let parts = hunk.header.split(separator: " ")
				guard parts.count >= 4,
						parts[1].hasPrefix("-"), parts[2].hasPrefix("+"),
						let oldRange = range(parts[1]), let newRange = range(parts[2])
				else
				{
					return false
				}
				let oldStart = oldRange.count == 0 ? oldRange.start : oldRange.start - 1
				let (start, overflow) = oldStart.addingReportingOverflow(offset)
				guard !overflow, start >= 0, start <= maximumMaterializedLines,
						oldRange.count <= maximumMaterializedLines - start,
						newRange.count <= maximumMaterializedLines,
						newRange.start == start + (newRange.count == 0 ? 0 : 1),
						extend(to: start + oldRange.count),
						current.count - oldRange.count <= maximumMaterializedLines - newRange.count
				else
				{
					return false
				}
				var consumed = 0
				var replacement: [Line] = []
				for patchLine in hunk.text.components(separatedBy: "\n").dropFirst()
				{
					guard let prefix = patchLine.first, prefix != "\\"
					else
					{
						continue
					}
					let text = String(patchLine.dropFirst())
					if prefix == "+"
					{
						guard replacement.count < newRange.count
						else
						{
							return false
						}
						replacement.append(Line(
							origin: nil,
							text: text
						))
					}
					else if prefix == " " || prefix == "-"
					{
						guard consumed < oldRange.count
						else
						{
							return false
						}
						var line = current[start + consumed]
						guard line.text?.utf8.elementsEqual(text.utf8) ?? true
						else
						{
							return false
						}
						line.text = text
						if let origin = line.origin
						{
							original[origin] = text
						}
						if prefix == " "
						{
							guard replacement.count < newRange.count
							else
							{
								return false
							}
							replacement.append(line)
						}
						consumed += 1
					}
				}
				guard consumed == oldRange.count,
						replacement.count == newRange.count
				else
				{
					return false
				}
				current.replaceSubrange(
					start ..< start + consumed,
					with: replacement
				)
				offset += newRange.count - oldRange.count
			}
			return true
		}

		private func range(_ value: Substring) -> (start: Int, count: Int)?
		{
			let parts = value.dropFirst().split(separator: ",")
			guard let first = parts.first, let start = Int(first),
					let count = parts.count == 1 ? 1 : Int(parts[1]), start >= 0, count >= 0
			else
			{
				return nil
			}
			return (start, count)
		}

		func diff() -> String?
		{
			let before = original.enumerated().map
			{
				index, text in
				text.map(Token.text) ?? .unknown(index)
			}
			let after = current.map
			{
				line in
				line.text.map(Token.text) ?? .unknown(line.origin ?? -1)
			}
			var prefix = 0
			while prefix < min(
				before.count,
				after.count
			), before[prefix] == after[prefix]
			{
				prefix += 1
			}
			var oldEnd = before.count
			var newEnd = after.count
			while oldEnd > prefix, newEnd > prefix, before[oldEnd - 1] == after[newEnd - 1]
			{
				oldEnd -= 1
				newEnd -= 1
			}
			let oldCount = oldEnd - prefix
			let newCount = newEnd - prefix
			// The standard difference algorithm can become quadratic on unrelated lines.
			guard oldCount == 0 || newCount <= maximumDifferenceProduct / oldCount
			else
			{
				return nil
			}
			let difference = Array(after[prefix ..< newEnd]).difference(
				from: Array(before[prefix ..< oldEnd])
			)
			var removed = Set<Int>()
			var inserted = Set<Int>()
			for change in difference
			{
				switch change
				{
				case .remove(
					let offset,
					_,
					_
				): removed.insert(prefix + offset)
				case .insert(
					let offset,
					_,
					_
				): inserted.insert(prefix + offset)
				}
			}
			var old = 0
			var new = 0
			var output: [String] = []
			while old < before.count || new < after.count
			{
				let oldStart = old
				let newStart = new
				var lines: [String] = []
				while removed.contains(old), old < before.count
				{
					if case .text(let text) = before[old]
					{
						lines.append("-" + text)
					}
					old += 1
				}
				while inserted.contains(new), new < after.count
				{
					if case .text(let text) = after[new]
					{
						lines.append("+" + text)
					}
					new += 1
				}
				if !lines.isEmpty
				{
					let oldCount = old - oldStart
					let newCount = new - newStart
					let oldLine = oldCount == 0 ? oldStart : oldStart + 1
					let newLine = newCount == 0 ? newStart : newStart + 1
					output.append("@@ -\(oldLine),\(oldCount) +\(newLine),\(newCount) @@")
					output.append(contentsOf: lines)
				}
				else
				{
					old += 1
					new += 1
				}
			}
			return output.joined(separator: "\n")
		}
	}
}
