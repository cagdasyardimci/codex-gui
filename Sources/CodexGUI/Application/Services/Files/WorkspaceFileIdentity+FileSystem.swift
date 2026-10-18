import Darwin
import Foundation

/// Filesystem-backed identity capture stays outside canonical workspace values.
extension WorkspaceFileIdentity
{
	init?(checkoutRoot: URL, relativePath: String)
	{
		guard !relativePath.hasPrefix("/"), !relativePath.contains("\0")
		else
		{
			return nil
		}
		var components: [String] = []
		for component in relativePath.split(separator: "/")
		{
			if component == "."
			{
				continue
			}
			if component == ".."
			{
				guard !components.isEmpty
				else
				{
					return nil
				}
				components.removeLast()
			}
			else
			{
				components.append(String(component))
			}
		}
		guard !components.isEmpty
		else
		{
			return nil
		}
		self.checkoutRoot = Self.canonicalRootPath(checkoutRoot)
		self.relativePath = components.joined(separator: "/")
	}
	/// realpath preserves the physical root, including macOS's /var and /tmp aliases. Missing
	/// suffixes retain the canonical existing ancestor so missing roots remain identifiable.
	static func canonicalRootPath(_ root: URL) -> String
	{
		var ancestor = root.standardizedFileURL
		var missingComponents: [String] = []
		while true
		{
			if let resolved = realpath(
				ancestor.path,
				nil
			)
			{
				defer
				{
					free(resolved)
				}
				var path = String(cString: resolved)
				for component in missingComponents.reversed()
				{
					path = URL(fileURLWithPath: path).appendingPathComponent(component).path
				}
				return path
			}
			guard ancestor.path != "/"
			else
			{
				return root.standardizedFileURL.path
			}
			missingComponents.append(ancestor.lastPathComponent)
			ancestor.deleteLastPathComponent()
		}
	}
}
