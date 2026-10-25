import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ChangesReviewViewControllerTests
{

	@Test func sectionActionsKeepSourceThreadTurnAndHunk() throws
	{
		_ = NSApplication.shared
		let first = reviewTurn(
			threadID: "thread-a",
			turnID: "turn-1"
		)
		let second = reviewTurn(
			threadID: "thread-a",
			turnID: "turn-2"
		)
		let controller = ChangesViewController()
		_ = controller.view
		var selectedTurnID: String?
		var markedReference: ReviewReference?
		var prepared: (ReviewRequestKind, ReviewReference)?
		controller.onSelectReviewTurn =
		{
			selectedTurnID = $0
		}
		controller.onSetReviewed =
		{
			reviewed, reference in
			if reviewed
			{
				markedReference = reference
			}
		}
		controller.onPrepareChangeRequest =
		{
			prepared = ($0, $1)
		}
		controller.render(snapshot(
			turns: [first, second],
			selected: first
		))

		let section = try #require(popUp(
			in: controller.view,
			label: "Change section in selected file"
		))
		section.selectItem(at: 1)
		sendAction(from: section)
		let diff = try #require(
			textView(
				in: controller.view,
				label: "Reported diff for selected file or section"
			)
		)
		#expect(diff.string.contains("+new value"))
		#expect(!diff.string.contains("+other section"))

		let reviewed = try #require(
			button(
				in: controller.view,
				label: "Mark selected file or section reviewed"
			)
		)
		reviewed.state = .on
		sendAction(from: reviewed)
		#expect(markedReference?.threadID == "thread-a")
		#expect(markedReference?.turnID == "turn-1")
		#expect(markedReference?.path == "src/renamed.swift")
		#expect(markedReference?.hunkID == first.files[0].hunks[0].id)

		let actions = try #require(
			popUp(
				in: controller.view,
				label: "Ask about or request revision of selected change"
			)
		)
		actions.selectItem(at: 2)
		sendAction(from: actions)
		#expect(prepared?.0 == .revision)
		#expect(prepared?.1 == markedReference)

		let turn = try #require(popUp(
			in: controller.view,
			label: "Review turn"
		))
		turn.selectItem(at: 1)
		sendAction(from: turn)
		#expect(selectedTurnID == "turn-2")
	}

	@Test func binaryChangeIsLabeledWithoutInventingTextSections() throws
	{
		_ = NSApplication.shared
		let file = ReviewFile(
			path: "asset.bin",
			previousPath: nil,
			reportedMovePath: nil,
			kind: .binary,
			hunks: [],
			diff: "",
			fingerprint: "binary-v1",
			explanation: "Binary change; text sections are unavailable."
		)
		let turn = ReviewTurn(
			threadID: "thread-a",
			turnID: "turn-binary",
			files: [file],
			validations: [],
			codeStateID: "binary-state",
			hasUnknownEarlierHistory: false
		)
		let controller = ChangesViewController()
		_ = controller.view
		controller.render(snapshot(
			turns: [turn],
			selected: turn
		))
		let table = try #require(tableView(in: controller.view))
		let cell = try #require(controller.tableView(
			table,
			viewFor: table.tableColumns.first,
			row: 0
		))
		let diff = try #require(
			textView(
				in: controller.view,
				label: "Reported diff for selected file or section"
			)
		)
		#expect(cell.accessibilityLabel()?.contains("Binary file asset.bin") == true)
		#expect(diff.string == "Binary change; text sections are unavailable.")
	}

	@Test(arguments: ["file", "project", "turn", "thread", "return", "owner"])
	func editorCompletionCannotUpdateAnotherSelectionOrEnableItsPendingRequest(change: String)
		async throws
	{
		_ = NSApplication.shared
		let operation = DeferredEditorOperation()
		let controller = ChangesViewController(openFile:
			{
				path, project, diff in
				try await operation.open(
					path: path,
					project: project,
					diff: diff
				)
			})
		_ = controller.view
		let original = reviewTurn(
			threadID: "thread-a",
			turnID: "turn-1"
		)
		var originalSnapshot = snapshot(
			turns: [original],
			selected: original
		)
		let sessionID = UUID()
		originalSnapshot.workspaceOwner = WorkspaceLifecycleOwnerReference(
			owner: .source(sessionID: sessionID),
			workspace: WorkspaceIdentity(
				sessionID: sessionID,
				canonicalCheckoutPath: "/tmp/project"
			)
		)
		controller.render(ReviewPresentation(originalSnapshot))
		let open = try #require(
			button(
				in: controller.view,
				label: "Open selected changed file in editor"
			)
		)
		open.performClick(nil)
		let firstTask = try #require(controller.editorHandoffTask)
		try await operation.waitForRequestCount(1)

		var next = reviewTurn(
			threadID: change == "thread" ? "thread-b" : "thread-a",
			turnID: change == "turn" ? "turn-2" : "turn-1"
		)
		if change == "file"
		{
			let file = next.files[0]
			let other = ReviewFile(
				path: "other.swift",
				previousPath: nil,
				reportedMovePath: nil,
				kind: .modified,
				hunks: file.hunks,
				diff: file.diff,
				fingerprint: "other-file",
				explanation: nil
			)
			next = ReviewTurn(
				threadID: next.threadID,
				turnID: next.turnID,
				files: [other],
				validations: next.validations,
				codeStateID: next.codeStateID,
				hasUnknownEarlierHistory: next.hasUnknownEarlierHistory
			)
		}
		let changesProject = change == "project" || change == "return"
		var nextSnapshot = snapshot(
			turns: [next],
			selected: next,
			projectPath: changesProject ? "/tmp/other-project" : "/tmp/project"
		)
		nextSnapshot.workspaceOwner = originalSnapshot.workspaceOwner
		if change == "owner"
		{
			nextSnapshot.workspaceSelectionEpoch += 1
		}
		controller.render(ReviewPresentation(nextSnapshot))
		if change == "return"
		{
			nextSnapshot = originalSnapshot
			controller.render(ReviewPresentation(nextSnapshot))
		}
		#expect(open.isEnabled)
		open.performClick(nil)
		let secondTask = try #require(controller.editorHandoffTask)
		try await operation.waitForRequestCount(2)
		#expect(!open.isEnabled)

		// A review-marker snapshot for the same selection must also retain the pending state.
		nextSnapshot.reviewedReferences = [
			ReviewReference(
				threadID: nextSnapshot.selectedReview!.threadID,
				turnID: nextSnapshot.selectedReview!.turnID,
				file: nextSnapshot.selectedReview!.files[0]
			)
		]
		controller.render(ReviewPresentation(nextSnapshot))
		#expect(!open.isEnabled)
		operation.complete(
			at: 0,
			result: .failure(CocoaError(.fileNoSuchFile))
		)
		await firstTask.value
		let status = try #require(
			label(
				in: controller.view,
				accessibilityLabel: "Editor handoff status"
			)
		)
		#expect(status.isHidden)
		#expect(!open.isEnabled)

		operation.complete(
			at: 1,
			result: .success("Current selection opened")
		)
		await secondTask.value
		#expect(status.stringValue == "Current selection opened")
		#expect(!status.isHidden)
		#expect(open.isEnabled)
	}

	private func reviewTurn(
		threadID: String,
		turnID: String
	) -> ReviewTurn
	{
		let first = ReviewHunk(
			id: "hunk-1",
			header: "@@ -1 +1 @@",
			text: "@@ -1 +1 @@\n-old\n+new value",
			fingerprint: "hunk-one"
		)
		let second = ReviewHunk(
			id: "hunk-2",
			header: "@@ -9 +9 @@",
			text: "@@ -9 +9 @@\n-old\n+other section",
			fingerprint: "hunk-two"
		)
		let file = ReviewFile(
			path: "src/renamed.swift",
			previousPath: "src/original.swift",
			reportedMovePath: "src/renamed.swift",
			kind: .renamed,
			hunks: [first, second],
			diff: "\(first.text)\n\(second.text)",
			fingerprint: "file-v1",
			explanation: nil
		)
		let validation = ReviewValidation(
			threadID: threadID,
			turnID: turnID,
			itemID: "command-1",
			command: "swift test",
			cwd: "/tmp/project",
			output: "1 test passed",
			exitCode: 0,
			outcome: .succeeded,
			currency: .outdated,
			codeStateID: "before-edit",
			hasUnknownEarlierHistory: false
		)
		return ReviewTurn(
			threadID: threadID,
			turnID: turnID,
			files: [file],
			validations: [validation],
			codeStateID: "after-edit",
			hasUnknownEarlierHistory: false
		)
	}

	private func snapshot(
		turns: [ReviewTurn],
		selected: ReviewTurn,
		projectPath: String = "/tmp/project"
	) -> ConversationSnapshot
	{
		var snapshot = ConversationSnapshot(
			projectPath: projectPath,
			threads: [],
			selectedThreadID: selected.threadID,
			entries: [],
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "",
			canSend: false,
			accountDescription: "",
			backendDescription: "",
			executionState: .ready,
			statusMessage: nil,
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: [],
			recentProjects: []
		)
		snapshot.reviewTurns = turns
		snapshot.selectedReviewTurnID = selected.turnID
		snapshot.selectedReview = selected
		return snapshot
	}

	private func sendAction(from control: NSControl)
	{
		guard let action = control.action
		else
		{
			return
		}
		NSApplication.shared.sendAction(
			action,
			to: control.target,
			from: control
		)
	}

	private func popUp(
		in view: NSView,
		label: String
	) -> NSPopUpButton?
	{
		if let control = view as? NSPopUpButton, control.accessibilityLabel() == label
		{
			return control
		}
		return view.subviews.lazy.compactMap
		{
			popUp(
				in: $0,
				label: label
			)
		}.first
	}

	private func button(
		in view: NSView,
		label: String
	) -> NSButton?
	{
		if let control = view as? NSButton, control.accessibilityLabel() == label
		{
			return control
		}
		return view.subviews.lazy.compactMap
		{
			button(
				in: $0,
				label: label
			)
		}.first
	}

	private func segmentedControl(
		in view: NSView,
		label: String
	) -> NSSegmentedControl?
	{
		if let control = view as? NSSegmentedControl, control.accessibilityLabel() == label
		{
			return control
		}
		return view.subviews.lazy.compactMap
		{
			segmentedControl(
				in: $0,
				label: label
			)
		}.first
	}

	private func label(
		in view: NSView,
		accessibilityLabel: String
	) -> NSTextField?
	{
		if let field = view as? NSTextField, field.accessibilityLabel() == accessibilityLabel
		{
			return field
		}
		return view.subviews.lazy
			.compactMap
			{
				label(
					in: $0,
					accessibilityLabel: accessibilityLabel
				)
			}
			.first
	}

	private func textView(
		in view: NSView,
		label: String
	) -> NSTextView?
	{
		if let text = view as? NSTextView, text.accessibilityLabel() == label
		{
			return text
		}
		return view.subviews.lazy.compactMap
		{
			textView(
				in: $0,
				label: label
			)
		}.first
	}

	private func tableView(in view: NSView) -> NSTableView?
	{
		if let table = view as? NSTableView
		{
			return table
		}
		return view.subviews.lazy.compactMap
		{
			tableView(in: $0)
		}.first
	}
}

@MainActor
private final class DeferredEditorOperation
{
	private var continuations: [CheckedContinuation<String?, Error>] = []

	func open(
		path: String,
		project: URL,
		diff: String
	) async throws -> String?
	{
		try await withCheckedThrowingContinuation
		{
			continuation in
			continuations.append(continuation)
		}
	}

	func waitForRequestCount(_ count: Int) async throws
	{
		for _ in 0 ..< 1000
		{
			if continuations.count == count
			{
				return
			}
			await Task.yield()
		}
		try #require(
			continuations.count == count,
			"The editor operation must start before completing it"
		)
	}

	func complete(
		at index: Int,
		result: Result<String?, Error>
	)
	{
		continuations[index].resume(with: result)
	}
}
