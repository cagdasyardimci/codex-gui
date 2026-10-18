import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct GitDiffTreeRenderingTests
{
	@Test func diffOptionsAndPendingRefreshRetainNavigatorRows() async throws
	{
		let controller = GitChangesViewController(runtime: GitReviewRuntime(
			service: GitComparisonViewFixtureService()
		))
		defer
		{
			controller.close()
		}
		try await load(
			controller,
			identity: "tree-reuse"
		)
		let tree = try tree(in: controller.view)
		let roots = tree.rootItems
		let initialBuilds = controller.treeRenderCount
		var options = controller.runtime.state.options
		options.ignoreWhitespace.toggle()
		controller.runtime.setOptions(options)
		controller.runtime.reload()
		#expect(controller.treeRenderCount == initialBuilds)
		await controller.runtime.readTask?.value
		#expect(controller.treeRenderCount == initialBuilds)
		#expect(tree.rootItems.elementsEqual(
			roots,
			by:
			{
				$0 === $1
			}
		))

		controller.runtime.setFilter("Two")
		#expect(controller.treeRenderCount == initialBuilds + 1)
		controller.runtime.setFilter("")
		controller.runtime.toggleDirectory("Sources")
		#expect(controller.treeRenderCount == initialBuilds + 3)
		controller.runtime.selectFile("Tests/Two.swift")
		#expect(controller.treeRenderCount == initialBuilds + 4)
		let beforeOwnerChange = controller.treeRenderCount
		try await load(
			controller,
			identity: "another-owner"
		)
		#expect(controller.treeRenderCount == beforeOwnerChange + 1)
	}

	@Test func retainedSnapshotIdentityStillUpdatesChangedTreeCountsAndKind() async throws
	{
		let service = MutableTreeFixtureService()
		let controller = GitChangesViewController(runtime: GitReviewRuntime(service: service))
		defer
		{
			controller.close()
		}
		try await load(
			controller,
			identity: "tree-metadata"
		)
		let initialID = try #require(controller.runtime.state.snapshot).id
		let initialBuilds = controller.treeRenderCount
		await service.changeMetadata()
		controller.runtime.reload()
		await controller.runtime.readTask?.value
		#expect(controller.runtime.state.snapshot?.id == initialID)
		#expect(controller.treeRenderCount == initialBuilds + 1)
		let tree = try tree(in: controller.view)
		let root = try #require(tree.rootItems.first)
		let file = try #require(tree.children?(root).first)
		let details = try #require(tree.presentation?(file))
		#expect(details.accessories.compactMap
		{
			($0 as? NSTextField)?.stringValue
		} == [
			"+3",
			"-1"
		])
	}

	@Test func literalUnicodeDirectoriesAndSelectionsRemainIndependent() async throws
	{
		let directories = ["Caf\u{E9}", "Cafe\u{301}"]
		let paths = directories.map
		{
			"\($0)/Test.swift"
		}
		let controller = GitChangesViewController(runtime: GitReviewRuntime(
			service: GitComparisonViewFixtureService(paths: paths)
		))
		defer
		{
			controller.close()
		}
		try await load(
			controller,
			identity: "tree-unicode"
		)
		let tree = try tree(in: controller.view)
		try #require(tree.rootItems.count == 2)
		let roots = tree.rootItems
		for directory in directories
		{
			controller.runtime.toggleDirectory(directory)
		}
		#expect(controller.runtime.state.expandedDirectories.isEmpty)
		for (directory, path) in zip(
			directories,
			paths
		)
		{
			controller.runtime.toggleDirectory(directory)
			#expect(controller.runtime.state.expandedDirectories.count == 1)
			for root in roots
			{
				let details = try #require(tree.presentation?(root))
				#expect(tree.isItemExpanded(root) == details.path.utf8
					.elementsEqual(directory.utf8))
			}
			controller.runtime.selectFile(path)
			let selected = try #require(tree.selectedItem)
			#expect(Data(try #require(tree.presentation?(selected)).path.utf8) == Data(path.utf8))
			controller.runtime.toggleDirectory(directory)
		}
	}

	private func load(
		_ controller: GitChangesViewController,
		identity: String
	) async throws
	{
		let model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
			canonicalCheckoutPath: "/fixture/Review"
		))
		controller.activate(owner: FeaturePresentationOwner(
			WorkspaceSelectors.snapshot(
				model: model,
				now: .distantPast
			),
			storeIdentity: identity
		))
		await controller.runtime.readTask?.value
		_ = try #require(controller.runtime.state.snapshot)
	}

	private func tree(in view: NSView) throws -> ViewerFileTreeView
	{
		try #require(descendants(view).compactMap
		{
			$0 as? ViewerFileTreeView
		}.first)
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap
		{
			descendants($0)
		}
	}
}

private actor MutableTreeFixtureService: GitComparisonService
{
	private var fixture = GitComparisonViewFixtureService(paths: ["Sources/One.swift"])

	func changeMetadata()
	{
		fixture.additions = 3
		fixture.kind = .added
	}

	func compare(_ request: GitComparisonRequest) async -> GitComparisonResult
	{
		await fixture.compare(request)
	}
}
