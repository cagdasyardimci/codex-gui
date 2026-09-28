import Foundation

/// Scope prevents a late page from an older project or connection from owning current history.
struct HistoryPageScope: Equatable
{
	let projectPath: String
	let generation: Int
	let cursor: String
}
