import Foundation

/// Routes retain the complete rendered owner, never just the selected thread's label.
enum ContextPanelDestination: String, CaseIterable
{
	case changes, subagents, sources, workspaceFiles, reportedChanges
}

struct ContextPanelRequest: Equatable
{
	let owner: FeaturePresentationOwner
	let destination: ContextPanelDestination
	var recordID: String? = nil
}
