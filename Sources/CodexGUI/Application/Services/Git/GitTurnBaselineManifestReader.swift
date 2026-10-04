import Foundation

/// Reuses immutable HEAD tree content only during one tracked-tree capture.
struct GitTurnBaselineManifestReader
{
	struct Manifest: Equatable
	{
		let paths: [String]
		let index: Data
		let headTree: Data
	}

	private struct HeadTree
	{
		let objectID: String
		let bytes: Data
		let paths: Set<String>
	}

	private let runCommand: ([String]) throws -> Data
	private var cachedHeadTree: HeadTree?

	init(commands: GitTurnBaselineGitCommands)
	{
		runCommand =
		{
			try commands.run($0)
		}
	}

	init(runCommand: @escaping ([String]) throws -> Data)
	{
		self.runCommand = runCommand
	}

	mutating func read() throws -> Manifest
	{
		try Task.checkCancellation()
		let index = try runCommand(["ls-files", "--stage", "-z"])
		let objectID = try resolveHeadTreeObjectID()
		let reusableHeadTree = cachedHeadTree.flatMap
		{
			$0.objectID == objectID ? $0 : nil
		}
		let headTreeBytes: Data
		if let reusableHeadTree
		{
			headTreeBytes = reusableHeadTree.bytes
		}
		else if let objectID
		{
			headTreeBytes = try runCommand(["ls-tree", "--full-tree", "-rz", objectID])
		}
		else
		{
			headTreeBytes = Data()
		}

		var paths = try Self.paths(
			in: index,
			isIndex: true
		)
		let headTreePaths = try reusableHeadTree?.paths ?? Self.paths(
			in: headTreeBytes,
			isIndex: false
		)
		paths.formUnion(headTreePaths)

		cachedHeadTree = objectID.map
		{
			HeadTree(
				objectID: $0,
				bytes: headTreeBytes,
				paths: headTreePaths
			)
		}
		try Task.checkCancellation()

		return Manifest(
			paths: paths.sorted(),
			index: index,
			headTree: headTreeBytes
		)
	}

	private func resolveHeadTreeObjectID() throws -> String?
	{
		let resolvedTree: Data
		do
		{
			resolvedTree = try runCommand(["rev-parse", "--verify", "HEAD^{tree}"])
		}
		catch
		{
			let peelingFailure = error
			try Task.checkCancellation()
			let head = try? runCommand(["rev-parse", "--verify", "HEAD"])
			try Task.checkCancellation()

			// An unborn HEAD has no tree; an existing but unreadable HEAD remains an error.
			guard head == nil
			else
			{
				throw peelingFailure
			}
			return nil
		}
		try Task.checkCancellation()

		return String(
			decoding: resolvedTree,
			as: UTF8.self
		).trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private static func paths(
		in bytes: Data,
		isIndex: Bool
	) throws -> Set<String>
	{
		try Task.checkCancellation()
		guard let text = String(
			data: bytes,
			encoding: .utf8
		)
		else
		{
			throw unavailable("A tracked filename has unsupported encoding.")
		}
		var paths: Set<String> = []
		for record in text.split(separator: "\0")
		{
			try Task.checkCancellation()
			guard let delimiter = record.firstIndex(of: "\t")
			else
			{
				throw unavailable("The Git tracked-file manifest is invalid.")
			}
			let path = String(record[record.index(after: delimiter)...])
			let fields = record[..<delimiter].split(separator: " ")
			guard fields.count == 3, GitTurnBaselineTreeReader.validPath(path)
			else
			{
				throw unavailable("The Git tracked-file manifest contains an invalid path.")
			}
			if fields[0] == "160000"
			{
				throw unavailable("Submodules are not supported by Last Turn capture.")
			}
			if isIndex && fields[2] != "0"
			{
				throw unavailable("Resolve the index conflicts before capturing a turn baseline.")
			}
			paths.insert(path)
		}
		return paths
	}

	private static func unavailable(_ message: String) -> GitTurnBaselineReadError
	{
		.failure(.lastTurnBaselineUnavailable(message))
	}
}
