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
			service: GitComparisonViewFixtureService(paths: paths)
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
		#expect(try button(
			"Collapse diff for \(paths[0])",
			in: controller.view
		).dispatchConfiguredAction())
		#expect(sections[1].superview != nil)
		_ = try source(in: sections[1])
		_ = try button(
			"Expand diff for \(paths[0])",
			in: controller.view
		)
		_ = try button(
			"Collapse diff for \(paths[1])",
			in: controller.view
		)
	}

	@Test func expandingAGapInAColonBearingPathPreservesTheOtherFilesSelection() async throws
	{
		let paths = ["Sources/One.swift", "Sources/One.swift:0:gap:Other.swift"]
		let controller = GitChangesViewController(runtime: GitReviewRuntime(
			service: GitComparisonViewFixtureService(paths: paths)
		))
		let window = host(controller)
		defer
		{
			controller.close()
			window.close()
		}
		try await load(
			controller,
			owner: owner("colon-path")
		)
		settle(window)
		let first = try section(
			paths[0],
			in: controller.view
		)
		let firstSource = try source(in: first)
		let selection = NSRange(
			location: 4,
			length: 9
		)
		firstSource.setSelectedRange(selection)
		let snapshot = try #require(controller.runtime.state.snapshot)
		let presentation = GitDiffPresentation(
			snapshot: snapshot,
			options: controller.runtime.state.options
		)
		let gap = try #require(presentation.file(paths[1])?.rows.first
		{
			$0.kind == .gap
		})
		let requests = controller.projectionCache.requestCount
		controller.runtime.expandGap(try #require(gap.gapID))
		settle(window)
		#expect(try section(
			paths[0],
			in: controller.view
		) === first)
		#expect(firstSource.selectedRange() == selection)
		#expect(controller.projectionCache.requestCount == requests + 1)
	}

	@Test func collapsingOneFileRetainsOtherSelectionsAndScrollOffsets() async throws
	{
		let controller =
			GitChangesViewController(
				runtime: GitReviewRuntime(service: GitComparisonViewFixtureService())
			)
		let window = host(controller)
		defer
		{
			controller.close()
			window.close()
		}
		try await load(
			controller,
			owner: owner("initial")
		)
		settle(window)
		let second = try section(
			"Tests/Two.swift",
			in: controller.view
		)
		let source = try self.source(in: second)
		let selection = NSRange(
			location: 2,
			length: 7
		)
		source.setSelectedRange(selection)
		let inner = try #require(source.enclosingScrollView)
		inner.contentView.scroll(to: NSPoint(
			x: 60,
			y: 0
		))
		inner.reflectScrolledClipView(inner.contentView)
		let horizontal = inner.contentView.bounds.origin.x
		#expect(horizontal > 0)
		let outer = try #require(second.enclosingScrollView)
		outer.contentView.scroll(to: NSPoint(
			x: 0,
			y: 20
		))
		outer.reflectScrolledClipView(outer.contentView)
		let vertical = outer.contentView.bounds.origin.y
		let requests = controller.projectionCache.requestCount
		#expect(try button(
			"Collapse diff for Sources/One.swift",
			in: controller.view
		).dispatchConfiguredAction())
		settle(window)
		#expect(try section(
			"Tests/Two.swift",
			in: controller.view
		) === second)
		#expect(try self.source(in: second) === source)
		#expect(source.selectedRange() == selection)
		#expect(inner.contentView.bounds.origin.x == horizontal)
		#expect(outer.contentView.bounds.origin.y == vertical)
		#expect(controller.projectionCache.requestCount == requests)
		#expect(try button(
			"Expand diff for Sources/One.swift",
			in: controller.view
		).dispatchConfiguredAction())
		#expect(try section(
			"Tests/Two.swift",
			in: controller.view
		) === second)
		#expect(controller.projectionCache.requestCount == requests + 1)
	}

	@Test func expandingOneFilesGapRetainsOtherViewsAndOuterScroll() async throws
	{
		let controller =
			GitChangesViewController(
				runtime: GitReviewRuntime(service: GitComparisonViewFixtureService())
			)
		let window = host(controller)
		defer
		{
			controller.close()
			window.close()
		}
		try await load(
			controller,
			owner: owner("initial")
		)
		settle(window)
		let first = try section(
			"Sources/One.swift",
			in: controller.view
		)
		let second = try section(
			"Tests/Two.swift",
			in: controller.view
		)
		let source = try self.source(in: second)
		let selection = NSRange(
			location: 4,
			length: 9
		)
		source.setSelectedRange(selection)
		let outer = try #require(second.enclosingScrollView)
		outer.contentView.scroll(to: NSPoint(
			x: 0,
			y: 20
		))
		let vertical = outer.contentView.bounds.origin.y
		let snapshot = try #require(controller.runtime.state.snapshot)
		let presentation = GitDiffPresentation(
			snapshot: snapshot,
			options: controller.runtime.state.options
		)
		let gap = try #require(presentation.file("Sources/One.swift")?.rows
			.first
			{
				$0.kind == .gap
			})
		let requests = controller.projectionCache.requestCount
		controller.runtime.expandGap(try #require(gap.gapID))
		settle(window)
		#expect(try section(
			"Sources/One.swift",
			in: controller.view
		) !== first)
		#expect(try section(
			"Tests/Two.swift",
			in: controller.view
		) === second)
		#expect(source.selectedRange() == selection)
		#expect(outer.contentView.bounds.origin.y == vertical)
		#expect(controller.projectionCache.requestCount == requests + 1)
	}

	@Test func contentOptionsAndOwnersInvalidateRetainedSections() async throws
	{
		let controller =
			GitChangesViewController(
				runtime: GitReviewRuntime(service: GitComparisonViewFixtureService())
			)
		let window = host(controller)
		defer
		{
			controller.close()
			window.close()
		}
		try await load(
			controller,
			owner: owner("initial")
		)
		#expect(controller.children.contains
		{
			$0 is GitDiffDocumentController
		})
		let initial = try section(
			"Tests/Two.swift",
			in: controller.view
		)
		controller.runtime.setFilter("Two")
		#expect(try section(
			"Tests/Two.swift",
			in: controller.view
		) === initial)
		var options = controller.runtime.state.options
		options.ignoreWhitespace = true
		controller.runtime.setOptions(options)
		let filtered = try section(
			"Tests/Two.swift",
			in: controller.view
		)
		#expect(filtered !== initial)
		#expect(try button(
			"Collapse all diffs",
			in: controller.view
		).dispatchConfiguredAction())
		_ = try button(
			"Expand all diffs",
			in: controller.view
		)
		try await load(
			controller,
			owner: owner("next-owner")
		)
		#expect(controller.runtime.state.snapshot?.id == "reuse-fixture")
		_ = try button(
			"Collapse all diffs",
			in: controller.view
		)
		let nextOwner = try section(
			"Tests/Two.swift",
			in: controller.view
		)
		#expect(nextOwner !== filtered)
		_ = try source(in: nextOwner)
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
		await controller.runtime.readTask?.value
		#expect(controller.runtime.state.owner == owner)
		#expect(controller.runtime.state.pendingRequest == nil)
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
		window.isReleasedWhenClosed = false
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
