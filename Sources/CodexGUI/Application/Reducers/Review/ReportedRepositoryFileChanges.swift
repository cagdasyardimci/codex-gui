/// Projects reported edits to lexical checkout-relative paths without changing backend records.
enum ReportedRepositoryFileChanges
{
	static func filter(
		_ changes: [FileChange],
		repositoryRoot: String?
	) -> [FileChange]
	{
		guard let repositoryRoot, repositoryRoot.hasPrefix("/")
		else
		{
			// Without a checkout, there is no reliable boundary for reported paths.
			return changes
		}
		let root = lexicalAbsolutePath(repositoryRoot)
		let prefix = root == "/" ? "/" : root + "/"
		func relativePath(_ path: String) -> String?
		{
			guard !path.isEmpty
			else
			{
				return nil
			}
			let absolute = path.hasPrefix("/") ? path : prefix + path
			let resolved = lexicalAbsolutePath(absolute)
			guard resolved.utf8.starts(with: prefix.utf8),
					resolved.utf8.count > prefix.utf8.count
			else
			{
				return nil
			}
			return String(
				decoding: resolved.utf8.dropFirst(prefix.utf8.count),
				as: UTF8.self
			)
		}
		return changes.compactMap
		{
			change in
			guard let path = relativePath(change.path)
			else
			{
				return nil
			}
			var kind = ["type": change.kind]
			if let movePath = change.movePath
			{
				guard let destination = relativePath(movePath)
				else
				{
					return nil
				}
				kind["move_path"] = destination
			}
			return FileChange(json: ["path": path, "kind": kind, "diff": change.diff])
		}
	}

	/// Slash and dot-segment normalization must preserve every filename's original UTF-8 bytes.
	private static func lexicalAbsolutePath(_ path: String) -> String
	{
		var components: [String] = []
		for bytes in path.utf8.split(separator: UInt8(ascii: "/"))
		{
			let component = String(
				decoding: bytes,
				as: UTF8.self
			)
			switch component
			{
			case ".": continue
			case "..":
				if !components.isEmpty
				{
					components.removeLast()
				}
			default: components.append(component)
			}
		}
		return "/" + components.joined(separator: "/")
	}

}
