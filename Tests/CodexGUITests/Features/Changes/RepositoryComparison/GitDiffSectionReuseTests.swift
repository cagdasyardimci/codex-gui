import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct GitDiffSectionReuseTests
{
	@Test func canonicallyEquivalentPathsKeepDistinctSectionsAndSourceBytes() async throws
	{
		let paths = ["Sources/Caf\u{E9}.swift", "Sources/Cafe\u{301}.swift"]
		#expect(paths[0] == paths[1])
		#expect(Data(paths[0].utf8) != Data(paths[1].utf8))
		let controller = GitChangesViewController(runtime: GitReviewRuntime(
			service: ReuseFixtureService(paths: paths)
		))
		let window = host(controller)
		defer
		{
			controller.close()
			window.close()
		}
		try await load(
			controller,
			owner: owner("distinct-paths")
		)
		settle(window)
		let sections = descendants(controller.view).compactMap
		{
			$0 as? GitDiffFileSectionView
		}
		try #require(sections.count == 2)
		let sourcePaths = try sections.map
		{
			section in
			let sources = descendants(section).compactMap
			{
				$0 as? GitDiffTextView
			}
			try #require(!sources.isEmpty)
			let text = sources.map(\.string).joined(separator: "\n")
			return Data(text.utf8)
		}
		#expect(sourcePaths.count == 2)
		#expect(sourcePaths[0] != sourcePaths[1])
		for (sourceText, path) in zip(
			sourcePaths,
			paths
		)
		{
			#expect(sourceText.range(of: Data(path.utf8)) != nil)
		}
		#expect(controller.projectionCache.projectionCount == 2)
		let snapshot = try #require(controller.runtime.state.snapshot)
		let command = try #require(snapshot.copyCommand)
		#expect(command.hasPrefix("printf '%s' '" + snapshot.patch.base64EncodedString() + "'"))
		for path in paths
		{
			#expect(snapshot.patch.range(of: Data(("+++ b/" + path).utf8)) != nil)
		}
		let tree = try #require(descendants(controller.view).compactMap
		{
			$0 as? ViewerFileTreeView
		}.first)
		#expect(tree.numberOfRows == 3)
		let nodes = try (0 ..< tree.numberOfRows).compactMap
		{
			index -> NSObject? in
			let item = try #require(tree.item(atRow: index) as? NSObject)
			return tree.isExpandable?(item) == true ? nil : item
		}
		#expect(nodes.count == 2)
		for path in paths
		{
			let node = try #require(nodes.first
			{
				tree.presentation?($0).path.utf8.elementsEqual(path.utf8) == true
			})
			tree.selectRowIndexes(
				IndexSet(integer: tree.row(forItem: node)),
				byExtendingSelection: false
			)
			#expect(controller.runtime.state.selectedFileID?.utf8.elementsEqual(path.utf8) == true)
		}
		let other = try section(
			paths[1],
			in: controller.view
		)
		let gap = try #require(GitDiffPresentation(snapshot: snapshot).file(paths[0])?.rows.first
		{
			$0.kind == .gap
		})
		let requests = controller.projectionCache.requestCount
		controller.runtime.expandGap(try #require(gap.gapID))
		#expect(try section(
			paths[1],
			in: controller.view
		) === other)
		#expect(controller.projectionCache.requestCount == requests + 1)
		let collapse = try button(
			"Collapse diff for \(paths[0])",
			in: controller.view
		)
		#expect(collapse.dispatchConfiguredAction())
		_ = try button(
			"Expand diff for \(paths[0])",
			in: controller.view
		)
		#expect(try section(
			paths[1],
			in: controller.view
		) === other)
	}

	private func owner(_ identity: String) -> FeaturePresentationOwner
	{
		let model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
			canonicalCheckoutPath: "/fixture/Review"
		))
		return FeaturePresentationOwner(
			WorkspaceSelectors.snapshot(
				model: model,
				now: .distantPast
			),
			storeIdentity: identity
		)
	}

	private func load(
		_ controller: GitChangesViewController,
		owner: FeaturePresentationOwner
	) async throws
	{
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
		#expect(controller.runtime.state.owner == owner)
		_ = try #require(controller.runtime.state.snapshot)
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
			$0.accessibilityLabel()?.utf8.elementsEqual(label.utf8) == true
		})
	}

	private func section(
		_ file: String,
		in view: NSView
	) throws -> GitDiffFileSectionView
	{
		try #require(descendants(view).compactMap
		{
			$0 as? GitDiffFileSectionView
		}.first
		{
			descendants($0).contains
			{
				$0.accessibilityLabel()?.utf8
					.elementsEqual("Collapse diff for \(file)".utf8) == true
			}
		})
	}

	private func source(in section: NSView) throws -> GitDiffTextView
	{
		try #require(descendants(section).compactMap
		{
			$0 as? GitDiffTextView
		}.first)
	}

	private func host(_ controller: NSViewController) -> NSWindow
	{
		_ = NSApplication.shared
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 900,
				height: 300
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		window.contentViewController = controller
		return window
	}

	private func settle(_ window: NSWindow)
	{
		for _ in 0 ..< 5
		{
			window.layoutIfNeeded()
			window.contentView?.layoutSubtreeIfNeeded()
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

private struct ReuseFixtureService: GitComparisonService
{
	var paths = ["Sources/One.swift", "Tests/Two.swift"]
	var kinds: [GitComparisonChangeKind] = []

	func compare(_ request: GitComparisonRequest) async -> GitComparisonResult
	{
		let long = String(
			repeating: "wide source ",
			count: 60
		)
		let files = paths.enumerated().map
		{
			index, path in
			let kind = kinds.indices.contains(index) ? kinds[index] : .modified
			let context = (1 ... 12).map
			{
				" \(path) \(long)\($0)"
			}.joined(separator: "\n")
			let hunkText = "@@ -1,13 +1,13 @@\n\(context)\n-before\n+after\n"
			let patch = "diff --git a/\(path) b/\(path)\n--- a/\(path)\n+++ b/\(path)\n" + hunkText
			return GitComparisonFile(
				oldPath: kind == .added ? nil : path,
				newPath: kind == .deleted ? nil : path,
				kind: kind,
				additions: 1,
				deletions: 1,
				isBinary: false,
				patch: patch,
				hunks: [GitComparisonHunk(
					header: "@@ -1,13 +1,13 @@",
					text: hunkText,
					oldStart: 1,
					newStart: 1
				)]
			)
		}
		let patch = files.map(\.patch).joined(separator: "\n")
		return .snapshot(GitComparisonSnapshot(
			request: request,
			id: "reuse-fixture",
			resolvedBase: "HEAD",
			resolvedTarget: "Working tree",
			patch: Data(patch.utf8),
			files: files
		))
	}
}
