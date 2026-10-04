import Foundation

/// Immutable workspace choices and aggregate task status reused across unchanged publications.
final class TaskWorkspacePresentation
{
	let choices: [TaskWorkspaceChoice]
	let statusSummary: String?

	init(
		choices: [TaskWorkspaceChoice],
		statusSummary: String?
	)
	{
		self.choices = choices
		self.statusSummary = statusSummary
	}
}
