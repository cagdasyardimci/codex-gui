import Foundation

struct GitDiffPresentationOptions: Equatable, Sendable
{
	var loadFullFiles = true
	var showWordDiffs = true
	var ignoreWhitespace = false
	var ignoreImports = false
	var expandedGapIDs: Set<String> = []
}
