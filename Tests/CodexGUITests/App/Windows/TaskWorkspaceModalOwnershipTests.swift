import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite(
	"Deferred task UI ownership"
)
struct TaskWorkspaceModalOwnershipTests
{

	@Test func savedPromptInsertionExpiresWhenAnotherConversationInTheSameProjectIsSelected()
	{
		_ = NSApplication.shared
		let controller = ProjectContextViewController()
		_ = controller.view
		var inserted: [String] = []
		controller.onInsertPrompt =
		{
			inserted.append($0)
		}
		controller.render(
			context: ProjectContext(),
			models: [],
			skills: [],
			ownerIdentity: "/tmp/shared-project",
			draftOwnerIdentity: "thread-a"
		)
		let completion = controller.makePromptInsertionReceiver(id: "prompt-a")
		controller.render(
			context: ProjectContext(),
			models: [],
			skills: [],
			ownerIdentity: "/tmp/shared-project",
			draftOwnerIdentity: "thread-b"
		)
		completion()
		#expect(inserted.isEmpty)
		controller.makePromptInsertionReceiver(id: "prompt-b")()
		#expect(inserted == ["prompt-b"])
	}

	@Test func receiverExpiresForSameCheckoutNewSessionSelectionEpochAndDraftLifetime()
	{
		_ = NSApplication.shared
		let workspaceID = UUID()
		let sessionID = UUID()
		let original = WorkspaceLifecycleOwnerReference(
			owner: .managed(
				workspaceID: workspaceID,
				sessionID: sessionID
			),
			workspace: WorkspaceIdentity(
				sessionID: sessionID,
				canonicalCheckoutPath: "/tmp/task-a"
			)
		)
		let replacementSession = UUID()
		let replacement = WorkspaceLifecycleOwnerReference(
			owner: .managed(
				workspaceID: workspaceID,
				sessionID: replacementSession
			),
			workspace: WorkspaceIdentity(
				sessionID: replacementSession,
				canonicalCheckoutPath: "/tmp/task-a"
			)
		)
		for change in ["session", "selection", "lifetime"]
		{
			let controller = ConversationViewController()
			_ = controller.view
			var received: [ComposerContextItem] = []
			controller.onAddContext =
			{
				received.append($0)
			}
			var initial = snapshot(
				project: "/tmp/task-a",
				thread: nil
			)
			initial.workspaceOwner = original
			initial.workspaceSelectionEpoch = 0
			initial.composerDraftLifetime = 0
			controller.render(initial)
			let expired = controller.makeContextAttachmentReceiver()
			var current = initial
			switch change
			{
			case "session": current.workspaceOwner = replacement
			case "selection":
				current.workspaceSelectionEpoch = 1
				controller.render(current)
				current.workspaceSelectionEpoch = 2
			default: current.composerDraftLifetime = 1
			}
			controller.render(current)
			let attachment = ComposerContextItem(
				kind: .textExcerpt,
				title: "Captured old draft",
				excerpt: "Keep ownership"
			)
			expired(attachment)
			#expect(received.isEmpty)
			controller.makeContextAttachmentReceiver()(attachment)
			#expect(received == [attachment])
		}
	}

	@Test func projectMutationAndPromptReceiversRetainSessionEpochAndDraftOwnership()
	{
		_ = NSApplication.shared
		let originalSession = UUID()
		for change in ["session", "selection", "draft"]
		{
			let controller = ProjectContextViewController()
			_ = controller.view
			var updates: [ProjectContext] = []
			var inserted: [String] = []
			controller.onUpdate =
			{
				updates.append($0)
			}
			controller.onInsertPrompt =
			{
				inserted.append($0)
			}
			func render(
				session: UUID,
				epoch: Int,
				lifetime: Int
			)
			{
				let owner = "\(session)|/tmp/same-checkout|\(epoch)"
				controller.render(
					context: ProjectContext(),
					models: [],
					skills: [],
					ownerIdentity: owner,
					draftOwnerIdentity: owner + "|new|\(lifetime)"
				)
			}
			render(
				session: originalSession,
				epoch: 0,
				lifetime: 0
			)
			let mutation = controller.makeContextMutationReceiver
			{
				(value: inout ProjectContext, prompt: SavedPrompt) in
				value.savedPrompts = [prompt]
			}
			let prompt = controller.makePromptInsertionReceiver(id: "old-prompt")
			switch change
			{
			case "session": render(
					session: UUID(),
					epoch: 0,
					lifetime: 0
				)
			case "selection":
				render(
					session: originalSession,
					epoch: 1,
					lifetime: 0
				)
				render(
					session: originalSession,
					epoch: 2,
					lifetime: 0
				)
			default: render(
					session: originalSession,
					epoch: 0,
					lifetime: 1
				)
			}
			if change != "draft"
			{
				mutation(SavedPrompt(
					title: "Expired",
					instructions: "Do not overwrite"
				))
				#expect(updates.isEmpty)
			}
			prompt()
			#expect(inserted.isEmpty)
			controller.makePromptInsertionReceiver(id: "fresh-prompt")()
			#expect(inserted == ["fresh-prompt"])
		}
	}

	private func snapshot(
		project: String,
		thread: String?
	) -> ConversationSnapshot
	{
		ConversationSnapshot(
			projectPath: project,
			threads: [],
			selectedThreadID: thread,
			entries: [],
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "",
			canSend: true,
			accountDescription: "Synthetic",
			backendDescription: "Synthetic",
			executionState: .ready,
			statusMessage: nil,
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: [],
			recentProjects: []
		)
	}
}
