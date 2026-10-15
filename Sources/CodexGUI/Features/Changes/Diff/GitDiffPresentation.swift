import Foundation

enum GitDiffRowKind: Equatable, Sendable
{
	case context, addition, deletion, gap
}

struct GitDiffRow: Identifiable, Equatable, Sendable
{
	let id: String
	var kind: GitDiffRowKind
	let text: String
	var oldLine: Int?
	var newLine: Int?
	var changedRanges: [NSRange] = []
	var gapID: String? = nil
	var hiddenLineCount = 0
	var canExpand = false
}

struct GitDiffFilePresentation: Equatable, Sendable
{
	let file: GitComparisonFile
	let rows: [GitDiffRow]
}

struct GitDiffTreeRow: Identifiable, Equatable
{
	let id: WorkspaceFileIdentity
	let name: String
	let path: String
	let depth: Int
	let isDirectory: Bool
	let fileID: String?
	let type: WorkspaceFileTypePresentation
}

/// A pure projection of immutable comparison bytes. Counts always belong to the raw snapshot.
struct GitDiffPresentation: Equatable, Sendable
{
	private static let wordTokenExpression = try? NSRegularExpression(pattern: #"\w+|\s+|[^\w\s]"#)

	let snapshot: GitComparisonSnapshot
	var options = GitDiffPresentationOptions()

	func file(_ id: String) -> GitDiffFilePresentation?
	{
		guard let file = snapshot.files.first(where:
			{
				$0.id == id
			})
		else
		{
			return nil
		}
		return self.file(
			file,
			projectedRows: projectedRows(for: file)
		)
	}

	/// Parsing and word differences do not depend on context-gap expansion.
	func projectedRows(for file: GitComparisonFile) -> [[GitDiffRow]]
	{
		var remainingWordDiffTokens = 16_384
		return file.hunks.enumerated().map
		{
			index, hunk in
			let prefix = "\(snapshot.id):\(file.id):\(index)"
			let parsed = Self.parse(
				hunk,
				prefix: prefix
			)
			let filtered = filterChanges(
				parsed,
				path: file.path,
				remainingWordDiffTokens: &remainingWordDiffTokens
			)
			return filtered
		}
	}

	func file(
		_ file: GitComparisonFile,
		projectedRows: [[GitDiffRow]]
	) -> GitDiffFilePresentation
	{
		let rows = projectedRows.enumerated().flatMap
		{
			index, hunkRows in
			let prefix = "\(snapshot.id):\(file.id):\(index)"
			return foldContext(
				hunkRows,
				prefix: prefix
			)
		}
		return GitDiffFilePresentation(
			file: file,
			rows: rows
		)
	}

	/// Filtering keeps ancestors and opens matching paths so a result is always reachable.
	func treeRows(
		filter: String = "",
		expandedDirectories: Set<String> = []
	) -> [GitDiffTreeRow]
	{
		let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
		let files = snapshot.files.filter
		{
			query.isEmpty || $0.path.localizedCaseInsensitiveContains(query)
				|| ($0.oldPath?.localizedCaseInsensitiveContains(query) ?? false)
		}
		var entries: [String: String?] = [:]
		for file in files
		{
			let components = file.path.split(separator: "/").map(String.init)
			guard !components.isEmpty
			else
			{
				continue
			}
			for count in 1 ... components.count
			{
				let path = components.prefix(count).joined(separator: "/")
				if count == components.count
				{
					entries[path] = .some(file.id)
				}
				else if entries[path] == nil
				{
					entries[path] = .some(nil)
				}
			}
		}
		// The service captures the checkout root.
		// Projection must not consult live filesystem state.
		let root = snapshot.request.repositoryRoot
		return entries.keys.sorted().compactMap
		{
			path in
			let components = path.split(separator: "/")
			let ancestors = (1 ..< components.count).map
			{
				components.prefix($0).joined(separator: "/")
			}
			guard !query.isEmpty || ancestors.allSatisfy(expandedDirectories.contains)
			else
			{
				return nil
			}
			let fileID = entries[path] ?? nil
			let isDirectory = fileID == nil
			return GitDiffTreeRow(
				id: WorkspaceFileIdentity(
					checkoutRootPath: root,
					normalizedRelativePath: path
				),
				name: String(components.last ?? ""),
				path: path,
				depth: components.count - 1,
				isDirectory: isDirectory,
				fileID: fileID,
				type: WorkspaceFileTypePresentation(
					relativePath: path,
					isDirectory: isDirectory
				)
			)
		}
	}

	private static func parse(
		_ hunk: GitComparisonHunk,
		prefix: String
	) -> [GitDiffRow]
	{
		var oldLine = hunk.oldStart
		var newLine = hunk.newStart
		var rows: [GitDiffRow] = []
		// Split only on LF: Unicode line separators can be valid source text.
		for (index, line) in hunk.text.components(separatedBy: "\n").enumerated()
		{
			guard let marker = line.first, " +-".contains(marker)
			else
			{
				continue
			}
			let kind: GitDiffRowKind
			switch marker
			{
			case "+": kind = .addition
			case "-": kind = .deletion
			default: kind = .context
			}
			rows.append(GitDiffRow(
				id: "\(prefix):\(index)",
				kind: kind,
				text: String(line.dropFirst()),
				oldLine: kind == .addition ? nil : oldLine,
				newLine: kind == .deletion ? nil : newLine
			))
			if kind != .addition
			{
				oldLine += 1
			}
			if kind != .deletion
			{
				newLine += 1
			}
		}
		return rows
	}

	private func filterChanges(
		_ rows: [GitDiffRow],
		path: String,
		remainingWordDiffTokens: inout Int
	) -> [GitDiffRow]
	{
		// Without a complete lexical parser, retain imports when multiline syntax is present.
		let importFilteringAvailable = !rows.contains
		{
			row in
			["\"\"\"", "'''", "/*", "*/"].contains(where: row.text.contains)
		}
		var result: [GitDiffRow] = []
		var index = 0
		while index < rows.count
		{
			guard rows[index].kind != .context
			else
			{
				result.append(rows[index])
				index += 1
				continue
			}
			let start = index
			while index < rows.count, rows[index].kind != .context
			{
				index += 1
			}
			let block = Array(rows[start ..< index])
			let deleted = block.filter
			{
				$0.kind == .deletion
			}
			let added = block.filter
			{
				$0.kind == .addition
			}
			var replacements: [String: GitDiffRow] = [:]
			var hidden: Set<String> = []
			for (old, new) in zip(
				deleted,
				added
			)
			{
				if options.ignoreWhitespace,
					Self.withoutWhitespace(old.text) == Self.withoutWhitespace(new.text)
				{
					var context = new
					context.kind = .context
					context.oldLine = old.oldLine
					replacements[new.id] = context
					hidden.insert(old.id)
				}
				else if options.showWordDiffs
				{
					var oldRow = old
					var newRow = new
					let ranges = Self.changedSpans(
						old.text,
						new.text,
						remainingTokenBudget: &remainingWordDiffTokens
					)
					oldRow.changedRanges = ranges.old
					newRow.changedRanges = ranges.new
					replacements[old.id] = oldRow
					replacements[new.id] = newRow
				}
			}
			for row in block where !hidden.contains(row.id)
			{
				let replacement = replacements[row.id] ?? row
				if options.ignoreImports, importFilteringAvailable, replacement.kind != .context,
					Self.isImport(
					replacement.text,
					path: path
					)
				{
					continue
				}
				result.append(replacement)
			}
		}
		return result
	}

	private static func withoutWhitespace(_ text: String) -> String
	{
		String(text.filter
		{
			!$0.isWhitespace
		})
	}

	/// Limited syntax filtering, not an AST: only unindented, single-line Swift module imports
	/// and Python import/from statements. Multiline imports and other languages remain visible.
	/// A hunk with multiline string/comment delimiters disables this limited filter entirely.
	private static func isImport(
		_ text: String,
		path: String
	) -> Bool
	{
		let pattern: String
		switch URL(fileURLWithPath: path).pathExtension.lowercased()
		{
		case "swift":
			pattern = #"^(?:@testable |@_exported |@_implementationOnly )?import "#
				+ #"[A-Za-z_][A-Za-z0-9_.]*\s*$"#
		case "py", "pyw":
			let alias = #"(?: as [A-Za-z_][A-Za-z0-9_]*)?"#
			let module = #"[A-Za-z_][A-Za-z0-9_.]*"# + alias
			let name = #"[A-Za-z_][A-Za-z0-9_]*"# + alias
			pattern = "^(?:import " + module + "(?:, " + module + ")*"
				+ #"|from [A-Za-z_.][A-Za-z0-9_.]* import (?:\*|"#
				+ name + "(?:, " + name + #")*))\s*$"#
		default: return false
		}
		return text.range(
			of: pattern,
			options: .regularExpression
		) != nil
	}

	private func foldContext(
		_ rows: [GitDiffRow],
		prefix: String
	) -> [GitDiffRow]
	{
		var result: [GitDiffRow] = []
		var index = 0
		while index < rows.count
		{
			guard rows[index].kind == .context
			else
			{
				result.append(rows[index])
				index += 1
				continue
			}
			let start = index
			while index < rows.count, rows[index].kind == .context
			{
				index += 1
			}
			let count = index - start
			let gapID = "\(prefix):gap:\(rows[start].id):\(rows[index - 1].id)"
			guard count > 6,
					!(options.loadFullFiles && options.expandedGapIDs.contains(gapID))
			else
			{
				result.append(contentsOf: rows[start ..< index])
				continue
			}
			result.append(contentsOf: rows[start ..< start + 3])
			result.append(GitDiffRow(
				id: gapID,
				kind: .gap,
				text: "\(count - 6) unmodified lines",
				oldLine: nil,
				newLine: nil,
				gapID: gapID,
				hiddenLineCount: count - 6,
				canExpand: options.loadFullFiles
			))
			result.append(contentsOf: rows[index - 3 ..< index])
		}
		return result
	}

	private static func changedSpans(
		_ old: String,
		_ new: String,
		remainingTokenBudget: inout Int
	)
		-> (old: [NSRange], new: [NSRange])
	{
		guard remainingTokenBudget > 0
		else
		{
			return wholeLineSpans(
				old,
				new
			)
		}
		guard let expression = wordTokenExpression
		else
		{
			return ([], [])
		}
		func tokens(
			_ text: String,
			maximumCount: Int
		) -> [(text: String, range: NSRange)]?
		{
			let value = text as NSString
			var result: [(text: String, range: NSRange)] = []
			var exceededLimit = false
			expression.enumerateMatches(
				in: text,
				range: NSRange(
					location: 0,
					length: value.length
				)
			)
			{
				match, _, stop in
				guard let match
				else
				{
					return
				}
				guard result.count < maximumCount
				else
				{
					exceededLimit = true
					stop.pointee = true
					return
				}
				result.append((value.substring(with: match.range), match.range))
			}
			return exceededLimit ? nil : result
		}
		// Stop tokenizing once a line cannot fit the existing line or file budget.
		guard let oldTokens = tokens(
			old,
			maximumCount: min(
				2048,
				remainingTokenBudget
			)
		), let newTokens = tokens(
			new,
			maximumCount: min(
				2048,
				remainingTokenBudget - oldTokens.count
			)
		)
		else
		{
			return wholeLineSpans(
				old,
				new
			)
		}
		remainingTokenBudget -= oldTokens.count + newTokens.count
		let difference = newTokens.map(\.text).difference(from: oldTokens.map(\.text))
		var oldRanges: [NSRange] = []
		var newRanges: [NSRange] = []
		for change in difference
		{
			switch change
			{
			case .remove(
				let offset,
				_,
				_
			): oldRanges.append(oldTokens[offset].range)
			case .insert(
				let offset,
				_,
				_
			): newRanges.append(newTokens[offset].range)
			}
		}
		return (
			oldRanges.sorted
			{
				$0.location < $1.location
			},
			newRanges.sorted
			{
				$0.location < $1.location
			}
		)
	}

	private static func wholeLineSpans(
		_ old: String,
		_ new: String
	) -> (old: [NSRange], new: [NSRange])
	{
		(
			[NSRange(
				location: 0,
				length: (old as NSString).length
			)],
			[NSRange(
				location: 0,
				length: (new as NSString).length
			)]
		)
	}
}
