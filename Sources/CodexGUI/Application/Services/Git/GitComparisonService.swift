import Foundation

protocol GitComparisonService: Sendable
{
	func compare(_ request: GitComparisonRequest) async -> GitComparisonResult
}

/// Git receives argument arrays, with external diff and text converters explicitly disabled.
/// Fingerprints and repeated patch reads detect ordinary races; Git offers no atomic snapshot
/// of an independently edited working tree, so this cannot prove an atomic capture.
struct LocalGitComparisonService: GitComparisonService
{
	let baselineService: any GitTurnBaselineService

	init(baselineService: any GitTurnBaselineService = LocalGitTurnBaselineService.shared)
	{
		self.baselineService = baselineService
	}

	func compare(_ request: GitComparisonRequest) async -> GitComparisonResult
	{
		if request.scope == .lastTurn
		{
			if let changes = request.reportedChanges
			{
				return GitReportedTurnComparison.compare(
					changes,
					request: request
				)
			}
			return await baselineService.compare(request)
		}
		return await GitSubprocessCancellation.detached
		{
			var reader = GitComparisonReader(request: request)
			return reader.compare()
		}
	}
}

private struct GitComparisonReader
{
	let request: GitComparisonRequest
	private let maximumBytes = 8 * 1024 * 1024
	private var disabledFilters: [String] = []

	init(request: GitComparisonRequest)
	{
		self.request = request
	}

	mutating func compare() -> GitComparisonResult
	{
		guard FileManager.default.fileExists(atPath: request.repositoryRoot)
		else
		{
			return .unavailable(.repositoryUnavailable)
		}
		guard request.scope != .lastTurn
		else
		{
			return .unavailable(.lastTurnUnavailable)
		}
		do
		{
			let repositoryCheck = try? text(["rev-parse", "--is-inside-work-tree"])
			try Task.checkCancellation()
			guard let repositoryCheck,
					repositoryCheck.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
			else
			{
				return .unavailable(.notGitRepository)
			}
			try disableConfiguredFilters()
			return try readComparisonSnapshot()
		}
		catch let failure as GitComparisonReadError
		{
			switch failure
			{
			case .oversized: return .unavailable(.oversized)
			case .revision(let value): return .unavailable(.invalidRevision(value))
			case .command: return .unavailable(.failed("Git could not read this comparison."))
			}
		}
		catch is CancellationError
		{
			return .unavailable(.cancelled)
		}
		catch
		{
			return .unavailable(.failed("The comparison could not be read."))
		}
	}

	private func readComparisonSnapshot() throws -> GitComparisonResult
	{
		if request.scope == .staged || request.scope == .unstaged
		{
			let unmerged = try run(["ls-files", "--unmerged", "-z"])
			guard unmerged.isEmpty
			else
			{
				return .unavailable(.unmergedIndex)
			}
		}

		let before = try fingerprint()
		let comparison = try resolvedComparison()
		let arguments = [
			"diff",
			"--no-ext-diff",
			"--no-textconv",
			"--no-color",
			"--full-index",
			"--find-renames",
			"--src-prefix=a/",
			"--dst-prefix=b/",
			"--unified=2147483647"
		] + comparison.arguments + ["--"]
		let patch = try run(arguments)
		guard String(
			data: patch,
			encoding: .utf8
		) != nil
		else
		{
			return .unavailable(.unsupportedTextEncoding)
		}

		let repeatedPatch = try run(arguments)
		let after = try fingerprint()
		guard !GitComparisonPatchParser.hasUnsupportedSections(in: patch)
		else
		{
			return .unavailable(.unmergedIndex)
		}
		guard before == after, patch == repeatedPatch
		else
		{
			return .unavailable(.repositoryChanged)
		}
		try Task.checkCancellation()
		return .snapshot(GitComparisonSnapshot(
			request: request,
			id: UUID().uuidString,
			resolvedBase: comparison.base,
			resolvedTarget: comparison.target,
			patch: patch,
			files: GitComparisonPatchParser.files(in: patch)
		))
	}

	/// Clean filters can run while diff converts a working-tree file to repository form.
	/// Enumerate effective repository keys, including includes, then override every driver.
	private mutating func disableConfiguredFilters() throws
	{
		let names = try run(
			["config", "--includes", "--null", "--name-only", "--get-regexp", "^filter\\."],
			allowNoMatch: true
		)
		var drivers: Set<String> = []
		for name in String(
			decoding: names,
			as: UTF8.self
		).split(separator: "\0")
		{
			guard let separator = name.lastIndex(of: ".")
			else
			{
				continue
			}
			drivers.insert(String(name[..<separator]))
		}
		for driver in drivers.sorted()
		{
			for field in ["clean=", "smudge=", "process=", "required=false"]
			{
				disabledFilters += ["-c", driver + "." + field]
			}
		}
	}

	private func resolvedComparison() throws -> (arguments: [String], base: String, target: String)
	{
		switch request.scope
		{
		case .unstaged:
			return ([], "Index", "Working tree")
		case .staged:
			let head = try revision("HEAD")
			return (["--cached", head], head, "Index")
		case .uncommitted:
			let head = try revision("HEAD")
			return ([head], head, "Working tree (tracked files)")
		case .branch, .committed:
			let defaultBase = request.scope == .committed ? "HEAD^" : "HEAD"
			let base = try revision(request.baseRevision ?? defaultBase)
			let target = try revision(request.targetRevision ?? "HEAD")
			return ([base, target], base, target)
		case .lastTurn: throw GitComparisonReadError.command
		}
	}

	private func revision(_ value: String) throws -> String
	{
		guard !value.isEmpty, !value.contains("\0")
		else
		{
			throw GitComparisonReadError.revision(value)
		}
		do
		{
			return try text(["rev-parse", "--verify", "--end-of-options", value + "^{commit}"])
				.trimmingCharacters(in: .whitespacesAndNewlines)
		}
		catch
		{
			try Task.checkCancellation()
			throw GitComparisonReadError.revision(value)
		}
	}

	private func fingerprint() throws -> Data
	{
		var result = try run(["status", "--porcelain=v2", "-z", "--untracked-files=no"])
		result.append(try run(["for-each-ref", "--format=%(refname) %(objectname)"]))
		result.append((try? run(["rev-parse", "--verify", "HEAD"])) ?? Data())
		result.append((try? run(["symbolic-ref", "-q", "HEAD"])) ?? Data())
		result.append(try run(["ls-files", "--stage", "-z"]))
		return result
	}

	private func text(_ arguments: [String]) throws -> String
	{
		String(
			decoding: try run(arguments),
			as: UTF8.self
		)
	}

	/// The runner discards stderr so diagnostics cannot expose repository contents in the UI.
	private func run(
		_ arguments: [String],
		allowNoMatch: Bool = false
	) throws -> Data
	{
		let gitArguments = [
			"--no-optional-locks",
			"-c",
			"core.quotePath=true",
			"-c",
			"diff.ignoreSubmodules=none",
			"-c",
			"diff.submodule=short",
			"-c",
			"core.fsmonitor=false",
			"-C",
			request.repositoryRoot
		] + disabledFilters + arguments
		let output: GitCommandOutput
		do
		{
			output = try GitCommandRunner.run(
				arguments: gitArguments,
				maximumBytes: maximumBytes
			)
		}
		catch GitCommandRunnerError.oversized
		{
			throw GitComparisonReadError.oversized
		}
		let isSuccessful = output.terminationStatus == 0
		let isAllowedNoMatch = allowNoMatch && output.terminationStatus == 1
		guard isSuccessful || isAllowedNoMatch
		else
		{
			throw GitComparisonReadError.command
		}
		return output.bytes
	}
}

private enum GitComparisonReadError: Error
{
	case command
	case oversized
	case revision(String)
}

/// Header parsing stops at hunks, so added source lines cannot masquerade as Git metadata.
enum GitComparisonPatchParser
{
	static func hasUnsupportedSections(in data: Data) -> Bool
	{
		let patch = String(
			decoding: data,
			as: UTF8.self
		)
		return patch.components(separatedBy: "\n").contains(where: isUnsupportedSectionHeader)
	}

	static func files(in data: Data) -> [GitComparisonFile]
	{
		let text = String(
			decoding: data,
			as: UTF8.self
		)
		var sections: [[String]] = []
		for line in text.components(separatedBy: "\n")
		{
			if isUnsupportedSectionHeader(line)
			{
				sections.append([])
				continue
			}
			if line.hasPrefix("diff --git ")
			{
				sections.append([line])
			}
			else if !sections.isEmpty && !sections[sections.count - 1].isEmpty
			{
				sections[sections.count - 1].append(line)
			}
		}
		let supportedSections = sections.filter
		{
			!$0.isEmpty
		}
		let parsedFiles = supportedSections.map(file)
		return coalesced(parsedFiles)
	}

	private static func isUnsupportedSectionHeader(_ line: String) -> Bool
	{
		line.hasPrefix("diff --cc ") || line.hasPrefix("diff --combined ")
			|| line.hasPrefix("* Unmerged path ")
	}

	/// Git can emit deletion and addition sections for a symlink/regular-file type change.
	/// Coalescing preserves the payload while keeping path-based navigation identities unique.
	private static func coalesced(_ files: [GitComparisonFile]) -> [GitComparisonFile]
	{
		var positions: [String: Int] = [:]
		var result: [GitComparisonFile] = []
		for file in files
		{
			if let index = positions[file.path]
			{
				let previous = result[index]
				let rename = [previous, file].first
				{
					$0.kind == .renamed
				}
				result[index] = GitComparisonFile(
					oldPath: rename?.oldPath ?? previous.oldPath ?? file.oldPath,
					newPath: file.newPath ?? previous.newPath,
					kind: rename == nil ? .modified : .renamed,
					additions: previous.additions + file.additions,
					deletions: previous.deletions + file.deletions,
					isBinary: previous.isBinary || file.isBinary,
					patch: previous.patch + "\n" + file.patch,
					hunks: previous.hunks + file.hunks
				)
			}
			else
			{
				positions[file.path] = result.count
				result.append(file)
			}
		}
		return result
	}

	private static func file(_ lines: [String]) -> GitComparisonFile
	{
		let patch = lines.joined(separator: "\n")
		let metadata = lines.prefix
		{
			!$0.hasPrefix("@@ ")
		}
		var oldPath: String?
		var newPath: String?
		var kind: GitComparisonChangeKind = .modified
		for line in metadata
		{
			if line.hasPrefix("--- ")
			{
				oldPath = GitPatchSyntax.markerPath(
					String(line.dropFirst(4)),
					side: "a/"
				)
			}
			if line.hasPrefix("+++ ")
			{
				newPath = GitPatchSyntax.markerPath(
					String(line.dropFirst(4)),
					side: "b/"
				)
			}
			if line.hasPrefix("rename from ")
			{
				oldPath = GitPatchSyntax.decodedPath(String(line.dropFirst(12)))
				kind = .renamed
			}
			if line.hasPrefix("rename to ")
			{
				newPath = GitPatchSyntax.decodedPath(String(line.dropFirst(10)))
			}
			if line.hasPrefix("new file mode ")
			{
				kind = .added
			}
			if line.hasPrefix("deleted file mode ")
			{
				kind = .deleted
			}
		}
		// Mode-only and binary sections have no ---/+++ markers; same-path headers are enough.
		if oldPath == nil && newPath == nil,
			let fallback = samePathHeader(lines.first ?? "")
			?? GitDiffParser.filePaths(in: patch).first
		{
			oldPath = kind == .added ? nil : fallback
			newPath = kind == .deleted ? nil : fallback
		}
		let parsed = GitDiffParser.hunks(in: lines)
		let hunks = parsed.hunks.map
		{
			hunk in
			GitComparisonHunk(
				header: hunk.header,
				text: hunk.text,
				oldStart: start(
					in: hunk.header,
					marker: "-"
				),
				newStart: start(
					in: hunk.header,
					marker: "+"
				)
			)
		}
		return GitComparisonFile(
			oldPath: oldPath,
			newPath: newPath,
			kind: kind,
			additions: parsed.additions,
			deletions: parsed.deletions,
			isBinary: metadata
				.contains
				{
					$0.hasPrefix("Binary files ") || $0 == "GIT binary patch"
				},
			patch: patch,
			hunks: hunks
		)
	}

	/// Unquoted names may contain " b/"; only accept a split with identical paths.
	private static func samePathHeader(_ header: String) -> String?
	{
		GitPatchSyntax.unquotedHeaderCandidates(header).first
		{
			$0.old == $0.new
		}?.old
	}

	private static func start(
		in header: String,
		marker: String
	) -> Int
	{
		guard let range = header.range(
			of: marker + "[0-9]+",
			options: .regularExpression
		)
		else
		{
			return 0
		}
		return Int(header[range].dropFirst()) ?? 0
	}
}
