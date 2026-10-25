import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ProjectContextUITests
{
	@Test func typedContextModalReceiverRejectsAnotherCheckoutInTheSameStore()
	{
		_ = NSApplication.shared
		let controller = ProjectContextViewController()
		let sessionID = UUID()
		func snapshot(_ path: String) -> ConversationSnapshot
		{
			var result = ConversationSnapshot(
				projectPath: path,
				threads: [],
				selectedThreadID: "same-thread",
				entries: [],
				canLoadEarlierTurns: false,
				changedFiles: [],
				diff: "",
				draft: "",
				canSend: false,
				accountDescription: "Mock",
				backendDescription: "Mock",
				executionState: .ready,
				statusMessage: nil,
				models: [],
				selectedModelID: nil,
				selectedEffort: nil,
				pendingInteractions: [],
				recentProjects: []
			)
			result.workspaceOwner = WorkspaceLifecycleOwnerReference(
				owner: .source(sessionID: sessionID),
				workspace: WorkspaceIdentity(
					sessionID: sessionID,
					canonicalCheckoutPath: path
				)
			)
			return result
		}
		var updates: [ProjectContext] = []
		controller.onUpdate =
		{
			updates.append($0)
		}
		controller.render(ProjectContextPresentation(snapshot("/tmp/first")))
		let stale: (String) -> Void = controller.makeContextMutationReceiver
		{
			context, title in
			context.items.append(ProjectContextItem(
				id: "old",
				kind: .note,
				title: title,
				body: "old checkout"
			))
		}
		controller.render(ProjectContextPresentation(snapshot("/tmp/second")))
		stale("Late modal result")
		#expect(updates.isEmpty)
		let current: (String) -> Void = controller.makeContextMutationReceiver
		{
			context, title in
			context.items.append(ProjectContextItem(
				id: "current",
				kind: .note,
				title: title,
				body: "current checkout"
			))
		}
		current("Current edit")
		#expect(updates.count == 1)
		#expect(updates.first?.items.first?.title == "Current edit")
	}

	@Test func inclusionIsExplicitAndEditableInProjectPanel() throws
	{
		_ = NSApplication.shared
		let controller = ProjectContextViewController()
		let item = ProjectContextItem(
			id: "spec-1",
			kind: .specification,
			title: "API contract",
			body: "Use the documented endpoint",
			isIncluded: false
		)
		let context = ProjectContext(items: [item])
		var updated: ProjectContext?
		controller.onUpdate =
		{
			updated = $0
		}
		controller.render(
			context: context,
			models: [],
			skills: [],
			statusMessage: nil
		)
		let button = try #require(
			allSubviews(of: controller.view).compactMap
			{
				$0 as? NSButton
			}
			.first
			{
				$0.accessibilityLabel() == "Include API contract in requests"
			}
		)
		#expect(button.state == .off)
		button.performClick(nil)
		#expect(updated?.items.first?.isIncluded == true)
		#expect(updated?.includedContextText.contains("API contract") == true)
	}

	private func allSubviews(of view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap(allSubviews)
	}
}
