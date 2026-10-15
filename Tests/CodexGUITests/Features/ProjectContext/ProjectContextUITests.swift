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

	@Test func savedPromptSectionTracksTheRenderedProjectContext() throws
	{
		_ = NSApplication.shared
		let controller = ProjectContextViewController()
		let first = SavedPrompt(
			id: "first",
			title: "Review API",
			instructions: "Check compatibility"
		)
		let second = SavedPrompt(
			id: "second",
			title: "Explain change",
			instructions: "Describe behavior"
		)
		controller.render(
			context: ProjectContext(
				savedPrompts: [first],
				selectedPromptID: first.id
			),
			models: [],
			skills: [],
			statusMessage: nil
		)
		let firstButton = try #require(
			allSubviews(of: controller.view).compactMap
			{
				$0 as? NSButton
			}
			.first
			{
				$0.accessibilityLabel() == "Inspect saved prompt Review API"
			}
		)
		#expect(firstButton.title == "✓ Review API…")
		#expect(firstButton.toolTip == "Check compatibility")

		controller.render(
			context: ProjectContext(savedPrompts: [second]),
			models: [],
			skills: [],
			statusMessage: nil
		)
		let buttons = allSubviews(of: controller.view).compactMap
		{
			$0 as? NSButton
		}
		#expect(buttons
			.contains
			{
				$0.accessibilityLabel() == "Inspect saved prompt Explain change"
			})
		#expect(!buttons.contains
		{
			$0.accessibilityLabel() == "Inspect saved prompt Review API"
		})
		#expect(buttons.contains
		{
			$0.accessibilityLabel() == "Add Prompt…"
		})
	}

	@Test func selectedSkillShowsInvocationAndUnavailableChoice() throws
	{
		_ = NSApplication.shared
		let controller = ProjectContextViewController()
		var context = ProjectContext()
		context.selectedSkill = ProjectSkillSelection(
			name: "review",
			description: "Review code"
		)
		controller.render(
			context: context,
			models: [],
			skills: [],
			statusMessage: "Skill discovery unavailable"
		)
		let texts = allSubviews(of: controller.view)
			.compactMap
			{
				($0 as? NSTextField)?.stringValue
			}
		#expect(texts.contains
		{
			$0.contains("$review")
		})
		#expect(texts.contains("Skill discovery unavailable"))
		let menu = try #require(
			allSubviews(of: controller.view).compactMap
			{
				$0 as? NSPopUpButton
			}
			.first
			{
				$0.accessibilityLabel() == "Selected project skill"
			}
		)
		#expect(menu.selectedItem?.title == "Unavailable: review")
	}

	private func allSubviews(of view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap(allSubviews)
	}
}
