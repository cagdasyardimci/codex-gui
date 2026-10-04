import Foundation

/// Keeps enumeration and change monitoring scoped to the same visible project files.
enum ProjectFileIndexPathPolicy
{
	private static let ignoredDirectories: Set<String> = [
		".git",
		".build",
		"node_modules",
		"DerivedData",
		"build",
		"dist",
		".next",
	]

	static func ignoresDirectory(named name: String) -> Bool
	{
		name.hasPrefix(".") || ignoredDirectories.contains(name)
			|| name.hasSuffix(".app") || name.hasSuffix(".xcodeproj")
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
