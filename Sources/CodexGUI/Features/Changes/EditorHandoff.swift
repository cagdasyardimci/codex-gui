import Foundation

@MainActor
final class EditorHandoff
{
	private let editor: EditorOpeningService

	init(editor: EditorOpeningService = EditorOpeningService())
	{
		self.editor = editor
	}

	func open(
		path: String,
		project: URL,
		diff: String
	) async throws -> String?
	{
		let selectedDiff = GitDiffParser.selectedDiff(
			for: path,
			in: diff
		)
		return try await editor.open(
			path: path,
			project: project,
			line: GitDiffParser.relevantLine(in: selectedDiff) ?? 1
		)
	}
}
