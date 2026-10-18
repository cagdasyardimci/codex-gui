import Foundation

/// Generated trees are omitted from recursive search; direct browsing still lists them.
enum GeneratedProjectDirectoryPolicy
{
	private static let names: Set<String> = [
		".git",
		".build",
		"node_modules",
		"DerivedData",
		"build",
		"dist",
		".next",
	]

	static func excludes(_ name: String) -> Bool
	{
		names.contains(name) || name.hasSuffix(".app") || name.hasSuffix(".xcodeproj")
	}
}
