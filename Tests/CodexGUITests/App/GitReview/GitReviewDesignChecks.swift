import AppKit
import Testing

@testable import CodexGUI

/// Assertions shared by normal behavior tests and explicitly requested design renders.
@MainActor
struct GitReviewDesignChecks
{
	private let fixture = GitReviewDesignFixture()

	func verifyCanonicalFileNavigationAndLayout() async throws
	{
		let presentation = fixture.summaryPresentation(attachments: false)
		let controller = GitChangesViewController(
			runtime: GitReviewRuntime(service: DesignPreviewGitService())
		)
		controller.activate(owner: presentation.owner)
		defer
		{
			controller.close()
		}
		let snapshot = try await waitForGitReviewComparison(
			controller,
			owner: presentation.owner
		)
		#expect(snapshot.files.count == DesignPreviewGitService.fileCount)
		#expect(snapshot.additions == DesignPreviewGitService.fileCount * 3)
		#expect(snapshot.deletions == DesignPreviewGitService.fileCount * 2)
		verifyDisplayMenu(controller)
		let window = fixture.host(
			controller,
			size: NSSize(
				width: 1100,
				height: 760
			)
		)
		defer
		{
			window.close()
		}
		window.setContentSize(NSSize(
			width: 760,
			height: 760
		))
		window.layoutIfNeeded()
		controller.view.layoutSubtreeIfNeeded()
		let last = try #require(snapshot.files.last)
		#expect(controller.selectFile(
			snapshotID: snapshot.id,
			fileID: last.id,
			owner: presentation.owner
		))
		#expect(controller.runtime.state.selectedFileID == last.id)
		#expect(!controller.selectFile(
			snapshotID: "obsolete-comparison",
			fileID: last.id,
			owner: presentation.owner
		))
		#expect(controller.runtime.state.selectedFileID == last.id)
		let previous = try #require(fixture.descendants(controller.view).compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.accessibilityLabel() == "Previous changed file"
		})
		previous.performClick(nil)
		#expect(controller.runtime.state.selectedFileID == snapshot.files.dropLast().last?.id)
		controller.view.layoutSubtreeIfNeeded()
		window.setContentSize(NSSize(
			width: 420,
			height: 760
		))
		window.layoutIfNeeded()
		controller.view.layoutSubtreeIfNeeded()
		#expect(controller.view.frame.width == 420)
		for navigation in fixture.descendants(controller.view).compactMap(
			{
				$0 as? NSButton
			}
		).filter(
			{
				["Previous changed file", "Next changed file"]
					.contains($0.accessibilityLabel() ?? "")
			}
		)
		{
			let frame = navigation.convert(
				navigation.bounds,
				to: controller.view
			)
			#expect(!navigation.isHiddenOrHasHiddenAncestor)
			#expect(frame.minX >= 0 && frame.maxX <= controller.view.bounds.maxX)
		}
	}

	func verifyResponsiveDiffAndScope() async throws
	{
		let presentation = fixture.summaryPresentation(attachments: false)
		let controller = GitChangesViewController(
			runtime: GitReviewRuntime(service: DesignPreviewGitService())
		)
		controller.activate(owner: presentation.owner)
		defer
		{
			controller.close()
		}
		let snapshot = try await waitForGitReviewComparison(
			controller,
			owner: presentation.owner
		)
		let window = fixture.host(
			controller,
			size: NSSize(
				width: 420,
				height: 760
			)
		)
		defer
		{
			window.close()
		}
		let selected = try #require(snapshot.files.last)
		#expect(controller.selectFile(
			snapshotID: snapshot.id,
			fileID: selected.id,
			owner: presentation.owner
		))
		let previous = try #require(fixture.descendants(controller.view).compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.accessibilityLabel() == "Previous changed file"
		})
		previous.performClick(nil)
		#expect(controller.runtime.state.selectedFileID == snapshot.files.dropLast().last?.id)
		controller.view.layoutSubtreeIfNeeded()
		try verifyResponsiveDiff(
			controller,
			window: window,
			snapshot: snapshot,
			owner: presentation.owner
		)
		try await verifyManualLayoutAndScope(
			controller,
			window: window,
			owner: presentation.owner
		)
	}

	func verifyDarkReviewAppearanceAndRows() async throws
	{
		try await verifyDarkComparison(fixture.summaryPresentation(attachments: false))
	}

	func verifyFocusedReviewHost() async throws
	{
		let presentation = fixture.summaryPresentation(attachments: false)
		let controller = GitChangesViewController(
			runtime: GitReviewRuntime(service: DesignPreviewGitService())
		)
		controller.activate(owner: presentation.owner)
		defer
		{
			controller.close()
		}
		_ = try await waitForGitReviewComparison(
			controller,
			owner: presentation.owner
		)
		let window = fixture.host(
			controller,
			size: NSSize(
				width: 1100,
				height: 760
			)
		)
		defer
		{
			window.close()
		}
		controller.close()
		controller.activate(owner: presentation.owner)
		_ = try await waitForGitReviewComparison(
			controller,
			owner: presentation.owner
		)
		window.contentViewController = nil
		try verifyFocusedHost(
			controller,
			presentation: presentation
		)
	}

	private func verifyDisplayMenu(_ controller: GitChangesViewController)
	{
		let menu = controller.makeDiffDisplayMenu()
		#expect(menu.items.prefix(6).map(\.title) == [
			"Load full files",
			"Rich preview",
			"Word diffs",
			"Hide white space",
			"Hide imports",
			"Copy git apply command"
		])
		#expect(menu.items.prefix(6).allSatisfy
		{
			$0.image != nil
		})
		#expect(menu.items.prefix(6).map(\.state) == [.on, .off, .on, .off, .off, .off])
		#expect(menu.items.count == 8)
		#expect(menu.items[6].isSeparatorItem)
		#expect(menu.items[7].title == "Open reported turn changes")
		#expect(!menu.items[1].isEnabled)
		#expect(menu.items[1].toolTip?.contains("unavailable") == true)
	}

	private func verifyManualLayoutAndScope(
		_ controller: GitChangesViewController,
		window: NSWindow,
		owner: FeaturePresentationOwner
	) async throws
	{
		let initial = try #require(controller.runtime.state.snapshot)
		let selection = controller.runtime.state.selectedFileID
		let options = controller.runtime.state.options
		let switchLayout = try #require(fixture.descendants(controller.view).compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.accessibilityLabel() == "Switch diff layout"
		})
		#expect(try adaptiveDiff(controller).layoutPreference == .automatic)
		switchLayout.performClick(nil)
		try expectLayout(
			controller,
			window: window,
			width: 1400,
			preference: .unified,
			mode: .unified
		)
		try expectLayout(
			controller,
			window: window,
			width: 420,
			preference: .unified,
			mode: .unified
		)
		switchLayout.performClick(nil)
		try expectLayout(
			controller,
			window: window,
			width: 420,
			preference: .split,
			mode: .split
		)
		try expectLayout(
			controller,
			window: window,
			width: 1400,
			preference: .split,
			mode: .split
		)
		switchLayout.performClick(nil)
		try expectLayout(
			controller,
			window: window,
			width: 420,
			preference: .automatic,
			mode: .unified
		)
		#expect(controller.runtime.state.owner == owner)
		#expect(controller.runtime.state.snapshot == initial)
		#expect(controller.runtime.state.selectedFileID == selection)
		#expect(controller.runtime.state.options == options)
		let refs = try #require(fixture.descendants(controller.view).first
		{
			$0.accessibilityLabel() == "Revision comparison"
		})
		window.setContentSize(NSSize(
			width: 1100,
			height: 760
		))
		window.layoutIfNeeded()
		controller.view.layoutSubtreeIfNeeded()
		#expect(refs.isHiddenOrHasHiddenAncestor)
		controller.runtime.selectScope(.branch)
		try await waitForGitReviewComparison(
			controller,
			owner: owner
		)
		controller.view.layoutSubtreeIfNeeded()
		#expect(!refs.isHiddenOrHasHiddenAncestor)
		#expect(controller.runtime.state.selectedFileID == selection)
		#expect(controller.runtime.state.snapshot?.additions == initial.additions)
		#expect(controller.runtime.state.snapshot?.deletions == initial.deletions)
		#expect(controller.runtime.state.options == options)
		for scope in [GitComparisonScope.unstaged, .staged, .committed, .uncommitted]
		{
			controller.runtime.selectScope(scope)
			try await waitForGitReviewComparison(
				controller,
				owner: owner
			)
			#expect(controller.runtime.state.scope == scope)
			#expect(controller.runtime.state.snapshot?.request.scope == scope)
			#expect(refs.isHiddenOrHasHiddenAncestor == (scope != .committed))
			#expect(controller.runtime.state.selectedFileID == selection)
			#expect(controller.runtime.state.snapshot?.additions == initial.additions)
			#expect(controller.runtime.state.snapshot?.deletions == initial.deletions)
			#expect(controller.runtime.state.options == options)
		}
		switchLayout.performClick(nil)
		#expect(try adaptiveDiff(controller).layoutPreference == .unified)
		let alternateModel = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
			canonicalCheckoutPath: "/design-fixture/AlternateWorkspace"
		))
		let alternateOwner = FeaturePresentationOwner(
			WorkspaceSelectors.snapshot(
				model: alternateModel,
				now: .distantPast
			),
			storeIdentity: "alternate-offline-preview"
		)
		controller.activate(owner: alternateOwner)
		try await waitForGitReviewComparison(
			controller,
			owner: alternateOwner
		)
		#expect(try adaptiveDiff(controller).layoutPreference == .automatic)
		switchLayout.performClick(nil)
		#expect(try adaptiveDiff(controller).layoutPreference == .unified)
		controller.close()
		controller.activate(owner: owner)
		try await waitForGitReviewComparison(
			controller,
			owner: owner
		)
		#expect(try adaptiveDiff(controller).layoutPreference == .automatic)
		#expect(controller.runtime.state.options == options)
	}

	private func adaptiveDiff(_ controller: GitChangesViewController) throws -> GitAdaptiveDiffView
	{
		try #require(fixture.descendants(controller.view).compactMap
		{
			$0 as? GitAdaptiveDiffView
		}.first)
	}

	private func expectLayout(
		_ controller: GitChangesViewController,
		window: NSWindow,
		width: CGFloat,
		preference: GitDiffLayoutPreference,
		mode: GitAdaptiveDiffView.LayoutMode
	) throws
	{
		window.setContentSize(NSSize(
			width: width,
			height: 760
		))
		window.layoutIfNeeded()
		controller.view.layoutSubtreeIfNeeded()
		let diff = try adaptiveDiff(controller)
		#expect(diff.layoutPreference == preference)
		#expect(diff.layoutMode == mode)
	}

	private func verifyResponsiveDiff(
		_ controller: GitChangesViewController,
		window: NSWindow,
		snapshot: GitComparisonSnapshot,
		owner: FeaturePresentationOwner
	) throws
	{
		let selectedFileID = controller.runtime.state.selectedFileID
		let options = controller.runtime.state.options
		let navigatorToggle = try #require(fixture.descendants(controller.view).compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.accessibilityLabel() == "Toggle changed-file navigator"
		})
		for width: CGFloat in [1400, 420, 1400]
		{
			window.setContentSize(NSSize(
				width: width,
				height: 760
			))
			window.layoutIfNeeded()
			controller.view.layoutSubtreeIfNeeded()
			let diff = try #require(fixture.descendants(controller.view).compactMap
			{
				$0 as? GitAdaptiveDiffView
			}.first)
			#expect(diff.layoutMode == (width > 500 ? .split : .unified))
			if diff.layoutMode == .split
			{
				let oldSource = try #require(fixture.descendants(diff).compactMap
				{
					$0 as? NSTextView
				}.first
				{
					$0.accessibilityLabel()?.contains("old side of split diff") == true
				})
				let fileID = try #require(selectedFileID ?? snapshot.files.first?.id)
				let projected = try #require(GitDiffPresentation(
					snapshot: snapshot,
					options: options
				).file(fileID))
				let expected = projected.rows.filter
				{
					$0.kind != .addition && $0.kind != .gap
				}.map(\.text).joined(separator: "\n")
				let pasteboard = NSPasteboard(name: NSPasteboard.Name(
					"responsive-diff-copy-" + UUID().uuidString
				))
				defer
				{
					pasteboard.releaseGlobally()
				}
				pasteboard.declareTypes(
					[.string],
					owner: nil
				)
				oldSource.setSelectedRange(NSRange(
					location: 0,
					length: (oldSource.string as NSString).length
				))
				#expect(oldSource.writeSelection(
					to: pasteboard,
					type: .string
				))
				#expect(pasteboard.string(forType: .string) == expected)
				oldSource.setSelectedRange(NSRange(
					location: 0,
					length: 0
				))
			}
			#expect((diff.bounds.width >= 800) == (width > 500))
			#expect(controller.runtime.state.owner == owner)
			#expect(controller.runtime.state.snapshot == snapshot)
			#expect(controller.runtime.state.selectedFileID == selectedFileID)
			#expect(controller.runtime.state.options == options)
			#expect(navigatorToggle.accessibilityValue() as? String ==
				(width > 500 ? "Visible" : "Hidden"))
		}
		navigatorToggle.performClick(nil)
		controller.view.layoutSubtreeIfNeeded()
		#expect(navigatorToggle.accessibilityValue() as? String == "Hidden")
		#expect(controller.runtime.state.selectedFileID == selectedFileID)
		navigatorToggle.performClick(nil)
		controller.view.layoutSubtreeIfNeeded()
		#expect(navigatorToggle.accessibilityValue() as? String == "Visible")
		#expect(controller.runtime.state.snapshot == snapshot)
	}

	private func verifyDarkComparison(_ presentation: PinnedSummaryPresentation) async throws
	{
		let application = NSApplication.shared
		let previousAppearance = application.appearance
		application.appearance = NSAppearance(named: .darkAqua)
		defer
		{
			application.appearance = previousAppearance
		}
		let controller = GitChangesViewController(
			runtime: GitReviewRuntime(service: DesignPreviewGitService())
		)
		let window = fixture.host(
			controller,
			size: NSSize(
				width: 1100,
				height: 760
			),
			appearanceName: .darkAqua
		)
		controller.activate(owner: presentation.owner)
		defer
		{
			controller.close()
			window.close()
		}
		try await waitForGitReviewComparison(
			controller,
			owner: presentation.owner
		)
		try verifyDarkUnifiedRows()
	}

	private func verifyDarkUnifiedRows() throws
	{
		let rows = fixture.darkUnifiedRows()
		let controller = NSViewController()
		let surface = DesktopSurface(AppKitColorTokens.canvas)
		controller.view = surface
		let code = GitUnifiedCodeView(
			rows: rows,
			path: "Example.swift"
		)
		surface.addSubview(code)
		code.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			code.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
			code.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
			code.topAnchor.constraint(equalTo: surface.topAnchor),
		])
		let window = fixture.host(
			controller,
			size: NSSize(
				width: 880,
				height: 100
			),
			appearanceName: .darkAqua
		)
		defer
		{
			window.close()
		}
		let source = try #require(fixture.descendants(code).compactMap
		{
			$0 as? NSTextView
		}.first)
		#expect(source.string == rows.map(\.text).joined(separator: "\n"))
	}

	private func verifyFocusedHost(
		_ git: GitChangesViewController,
		presentation: PinnedSummaryPresentation
	) throws
	{
		git.isExpanded = false
		let inspector = InspectorViewController()
		inspector.renderSummary(
			presentation,
			visible: true
		)
		inspector.panels.register(
			git,
			for: .changes,
			providesHeader: true
		)
		let panes = WindowPaneController(
			navigation: NavigationViewController(),
			conversation: ConversationViewController(),
			inspector: inspector,
			layoutStore: nil
		)
		let chrome = WindowChromeViewController(
			split: panes.split,
			accountButton: NSButton()
		)
		inspector.onGitReviewDisplayChange =
		{
			[weak panes, weak chrome, weak git] focused in
			panes?.setGitReviewFocused(focused)
			chrome?.setGitReviewFocused(focused)
			git?.isExpanded = focused
		}
		let window = fixture.host(
			chrome,
			size: NSSize(
				width: 1200,
				height: 760
			)
		)
		defer
		{
			window.close()
		}
		#expect(inspector.open(ContextPanelRequest(
			owner: presentation.owner,
			destination: .changes
		)))
		window.layoutIfNeeded()
		panes.split.view.layoutSubtreeIfNeeded()
		#expect(!panes.isGitReviewFocused)
		#expect(!inspector.isGitReviewFocused)
		#expect(!panes.split.splitViewItems[0].isCollapsed)
		#expect(!panes.split.splitViewItems[1].isCollapsed)
		#expect(!panes.split.splitViewItems[2].isCollapsed)
		#expect(inspector.isShowingDetails)
		inspector.setGitReviewFocused(true)
		window.layoutIfNeeded()
		panes.split.view.layoutSubtreeIfNeeded()
		#expect(panes.isGitReviewFocused)
		#expect(inspector.isGitReviewFocused)
		#expect(panes.split.splitViewItems[0].isCollapsed)
		#expect(panes.split.splitViewItems[1].isCollapsed)
		#expect(inspector.view.frame.width >= window.contentView!.bounds.width - 2)
		inspector.showSummary()
		window.layoutIfNeeded()
		#expect(!panes.isGitReviewFocused)
		#expect(!panes.split.splitViewItems[1].isCollapsed)
	}

}
