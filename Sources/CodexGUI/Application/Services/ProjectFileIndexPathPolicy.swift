import Foundation

/// Keeps enumeration and change monitoring scoped to the same visible project files.
enum ProjectFileIndexPathPolicy
{
	static func ignoresDirectory(named name: String) -> Bool
	{
		name.hasPrefix(".") || GeneratedProjectDirectoryPolicy.excludes(name)
	}

	static func includes(
		relativePath: String,
		isDirectory: Bool
	) -> Bool
	{
		let components = relativePath.split(separator: "/").map(String.init)
		guard let name = components.last, !name.hasPrefix(".")
		else
		{
			return false
		}
		let directories = isDirectory ? components[...] : components.dropLast()
		return !directories.contains(where: ignoresDirectory(named:))
	}
}
