import Foundation

/// Shared navigation artwork metadata; filesystem and Git snapshots retain separate identities.
struct WorkspaceFileTypePresentation: Equatable
{
	let symbol: String
	let description: String

	init(
		relativePath: String,
		isDirectory: Bool = false,
		isSymbolicLink: Bool = false
	)
	{
		if isSymbolicLink
		{
			symbol = "link"
			description = "Symbolic link, preview unavailable"
		}
		else if isDirectory
		{
			symbol = "folder"
			description = "Folder"
		}
		else
		{
			switch URL(fileURLWithPath: relativePath).pathExtension.lowercased()
			{
			case "swift":
				symbol = "swift"
				description = "Swift source"
			case "md", "txt":
				symbol = "doc.text"
				description = "Text file"
			case "json", "yaml", "yml", "toml":
				symbol = "curlybraces"
				description = "Configuration file"
			default:
				symbol = "doc"
				description = "File"
			}
		}
	}
}
