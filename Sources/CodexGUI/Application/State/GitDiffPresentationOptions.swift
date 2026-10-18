import Foundation

struct GitDiffPresentationOptions: Equatable, Sendable
{
	var loadFullFiles = true
	var showWordDiffs = true
	var ignoreWhitespace = false
	var ignoreImports = false
	/// Gap IDs include literal Git file paths and must retain their exact UTF-8 identity.
	var expandedGapIDs: Set<Data> = []
}
