import Foundation

/// Limits reported edit presentation to paths within the selected checkout.
enum ReportedRepositoryFileChanges
{
	static func filter(
		_ changes: [FileChange],
		repositoryRoot: String?
	) -> [FileChange]
	{
		guard let repositoryRoot, NSString(string: repositoryRoot).isAbsolutePath
		else
		{
			// Without a checkout, there is no reliable boundary for reported paths.
			return changes
		}
		let root = URL(fileURLWithPath: repositoryRoot).standardizedFileURL
		let prefix = root.path == "/" ? "/" : root.path + "/"
		func contains(_ path: String) -> Bool
		{
			guard !path.isEmpty
			else
			{
				return false
			}
			let url = NSString(string: path).isAbsolutePath
				? URL(fileURLWithPath: path) : root.appendingPathComponent(path)
			let resolved = url.standardizedFileURL.path
			return resolved != root.path && resolved.hasPrefix(prefix)
		}
		return changes.filter
		{
			contains($0.path) && ($0.movePath.map(contains) ?? true)
		}
	}
}
