import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct GitReviewToolbarBehaviorTests
{
	@Test func collapsingDiffsKeepsHeadersAndSupportsIndividualReopenAndExpandAll() async throws
	{
		let model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
			canonicalCheckoutPath: "/fixture/Review"
		))
		let owner = FeaturePresentationOwner(
			WorkspaceSelectors.snapshot(
				model: model,
				now: .distantPast
			),
			storeIdentity: "toolbar-behavior"
		)
		let controller = GitChangesViewController(
			runtime: GitReviewRuntime(service: ToolbarFixtureService())
		)
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 900,
				height: 640
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentViewController = controller
		defer
		{
			controller.close()
			window.close()
		}
		controller.activate(owner: owner)
		for _ in 0 ..< 100
		{
			if controller.runtime.state.snapshot != nil,
				controller.runtime.state.pendingRequest == nil
			{
				break
			}
			await Task.yield()
		}
		_ = try #require(controller.runtime.state.snapshot)
		window.layoutIfNeeded()
		#expect(descendants(controller.view).compactMap
		{
			$0 as? GitAdaptiveDiffView
		}.count == 2)
		let directories = controller.runtime.state.expandedDirectories
		let selectedFileID = controller.runtime.state.selectedFileID
		let initialProjections = controller.projectionCache.projectionCount
		let initialRequests = controller.projectionCache.requestCount
		#expect(initialProjections == 2)
		#expect(initialRequests == 2)
		try button(
			"Collapse all diffs",
			in: controller.view
		).performClick(nil)
		#expect(descendants(controller.view).compactMap
		{
			$0 as? GitAdaptiveDiffView
		}.isEmpty)
		#expect(controller.projectionCache.requestCount == initialRequests)
		#expect(controller.projectionCache.projectionCount == initialProjections)
		#expect(try buttons(
			prefix: "Expand diff for ",
			in: controller.view
		).count == 2)
		try button(
			"Expand diff for Sources/One.swift",
			in: controller.view
		).performClick(nil)
		#expect(descendants(controller.view).compactMap
		{
			$0 as? GitAdaptiveDiffView
		}.count == 1)
		#expect(controller.projectionCache.cachedFileIDs == [
			"Sources/One.swift",
			"Tests/Two.swift"
		])
		#expect(controller.projectionCache.requestCount == initialRequests + 1)
		#expect(controller.projectionCache.projectionCount == initialProjections)
		try button(
			"Expand all diffs",
			in: controller.view
		).performClick(nil)
		#expect(descendants(controller.view).compactMap
		{
			$0 as? GitAdaptiveDiffView
		}.count == 2)
		#expect(controller.projectionCache.requestCount == initialRequests + 3)
		#expect(controller.projectionCache.projectionCount == initialProjections)
		#expect(controller.runtime.state.selectedFileID == selectedFileID)
		#expect(controller.runtime.state.expandedDirectories == directories)
		window.setContentSize(NSSize(
			width: 632,
			height: 640
		))
		window.layoutIfNeeded()
		controller.view.layoutSubtreeIfNeeded()
		for label in [
			"Refresh comparison",
			"Wrap code lines",
			"Collapse all diffs",
			"Switch diff layout"
		]
		{
			#expect(try button(
				label,
				in: controller.view
			).isHiddenOrHasHiddenAncestor)
		}
		for label in ["More comparison actions", "Jump to file", "Toggle changed-file navigator"]
		{
			#expect(try !button(
				label,
				in: controller.view
			).isHiddenOrHasHiddenAncestor)
		}
		let compactMenu = controller.makeDiffDisplayMenu()
		#expect(compactMenu.items.suffix(4).map(\.title) == [
			"Refresh comparison",
			"Wrap code lines",
			"Collapse all diffs",
			"Switch diff layout"
		])
		#expect(compactMenu.items.suffix(4).allSatisfy
		{
			$0.action != nil && $0.isEnabled
		})
		window.setContentSize(NSSize(
			width: 761,
			height: 640
		))
		window.layoutIfNeeded()
		controller.view.layoutSubtreeIfNeeded()
		for label in [
			"Refresh comparison",
			"Wrap code lines",
			"Collapse all diffs",
			"Switch diff layout"
		]
		{
			#expect(try !button(
				label,
				in: controller.view
			).isHiddenOrHasHiddenAncestor)
		}
		#expect(controller.makeDiffDisplayMenu().items.count == 8)
		window.setContentSize(NSSize(
			width: 360,
			height: 640
		))
		window.layoutIfNeeded()
		controller.view.layoutSubtreeIfNeeded()
		let path = try #require(descendants(controller.view).compactMap
		{
			$0 as? NSTextField
		}.first
		{
			$0.stringValue == "Sources/One.swift"
		})
		#expect(path.frame.height <= 20)
		#expect((path.superview?.frame.height ?? .infinity) <= 48)
	}

	private func button(
		_ label: String,
		in view: NSView
	) throws -> NSButton
	{
		try #require(descendants(view).compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.accessibilityLabel() == label
		})
	}

	private func buttons(
		prefix: String,
		in view: NSView
	) throws -> [NSButton]
	{
		descendants(view).compactMap
		{
			$0 as? NSButton
		}.filter
		{
			$0.accessibilityLabel()?.hasPrefix(prefix) == true
		}
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap
		{
			descendants($0)
		}
	}
}

private struct ToolbarFixtureService: GitComparisonService
{
	func compare(_ request: GitComparisonRequest) async -> GitComparisonResult
	{
		let patch = "@@ -1 +1 @@\n-before\n+after\n"
		let files = ["Sources/One.swift", "Tests/Two.swift"].map
		{
			path in
			GitComparisonFile(
				oldPath: path,
				newPath: path,
				kind: .modified,
				additions: 1,
				deletions: 1,
				isBinary: false,
				patch: patch,
				hunks: [GitComparisonHunk(
					header: "@@ -1 +1 @@",
					text: patch,
					oldStart: 1,
					newStart: 1
				)]
			)
		}
		return .snapshot(GitComparisonSnapshot(
			request: request,
			id: "toolbar-fixture",
			resolvedBase: "HEAD",
			resolvedTarget: "Working tree",
			patch: Data(patch.utf8),
			files: files
		))
	}
}
