import AppKit

struct ChatToolsKey: Hashable
{
	let workspace: WorkspaceLifecycleOwnerReference
	let conversation: ExecutionConversationIdentity
}

@MainActor
final class ChatToolsSession
{
	let tabs: ToolsTabViewController
	let files: FilesViewController
	var pane = WindowPaneController.ToolsPaneState()
	var filesProjectPath: String?

	init(
		tabs: ToolsTabViewController = ToolsTabViewController(),
		filesRuntime: FileViewerRuntime = FileViewerRuntime()
	)
	{
		self.tabs = tabs
		files = FilesViewController(runtime: filesRuntime)
	}
}
