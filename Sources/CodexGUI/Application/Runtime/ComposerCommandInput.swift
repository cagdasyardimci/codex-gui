import Foundation

enum ComposerCommandInput
{
	case handled(WorkspaceOperationHandle?)
	case message(
		String,
		CollaborationMode?
	)
}
