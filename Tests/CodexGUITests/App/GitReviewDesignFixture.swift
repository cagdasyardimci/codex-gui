import AppKit
import Testing

@testable import CodexGUI

/// Builds deterministic, offscreen design state for behavior checks and optional previews.
@MainActor
struct GitReviewDesignFixture
{

	func summaryPresentation(attachments: Bool) -> PinnedSummaryPresentation
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
			canonicalCheckoutPath: "/design-fixture/ExampleWorkspace"
		))
		model.conversations.selectedConversation = .thread("design-chat")
		var sections = ContextSummarySections()
		sections.changes = .available(SummaryChangeTotals(
			additions: DesignPreviewGitService.fileCount * 3,
			deletions: DesignPreviewGitService.fileCount * 2
		))
		sections.agents = .available(SummaryAgentProjection(
			identities: [],
			completedCount: 3,
			runningCount: 2,
			aggregationDescription: "Associated with this chat"
		))
		sections.sources = .available(attachments ? [
			SummarySourceReference(
				id: "attachment-diagram",
				label: "example-diagram.png",
				kind: .attachment,
				detailRecordID: "attachment-diagram"
			),
			SummarySourceReference(
				id: "attachment-notes",
				label: "example-notes.pdf",
				kind: .attachment,
				detailRecordID: "attachment-notes"
			)
		] : [
			SummarySourceReference(
				id: "tool-list",
				label: "List examples",
				kind: .tool
			),
			SummarySourceReference(
				id: "tool-read",
				label: "Read example",
				kind: .tool
			),
			SummarySourceReference(
				id: "web-example",
				label: "Search examples",
				kind: .web
			)
		])
		sections.availableDestinations = [.changes, .sources, .subagents]
		return PinnedSummaryPresentation(
			WorkspaceSelectors.snapshot(
				model: model,
				now: .distantPast
			),
			ownerIdentity: "offline-design-preview",
			sections: sections
		)
	}

	func host(
		_ controller: NSViewController,
		size: NSSize,
		appearanceName: NSAppearance.Name = .aqua
	) -> NSWindow
	{
		_ = NSApplication.shared
		let window = NSWindow(
			contentRect: NSRect(
				origin: .zero,
				size: size
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.appearance = NSAppearance(named: appearanceName)
		window.contentViewController = controller
		window.setContentSize(size)
		window.layoutIfNeeded()
		controller.view.layoutSubtreeIfNeeded()
		return window
	}

	func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap
		{
			descendants($0)
		}
	}
	func darkUnifiedRows() -> [GitDiffRow]
	{

		[
			GitDiffRow(
				id: "old-comment",
				kind: .deletion,
				text: "    // Previous review note.",
				oldLine: 22,
				newLine: nil,
				changedRanges: [NSRange(
					location: 7,
					length: 20
				)]
			),
			GitDiffRow(
				id: "old-code",
				kind: .deletion,
				text: "    let mode = []",
				oldLine: 23,
				newLine: nil
			),
			GitDiffRow(
				id: "new-comment",
				kind: .addition,
				text: "    // Updated review note.",
				oldLine: nil,
				newLine: 22,
				changedRanges: [NSRange(
					location: 7,
					length: 19
				)]
			),
			GitDiffRow(
				id: "new-code",
				kind: .addition,
				text: "    let mode = [.updated]",
				oldLine: nil,
				newLine: 23,
				changedRanges: [NSRange(
					location: 16,
					length: 8
				)]
			),
		]
	}

}
