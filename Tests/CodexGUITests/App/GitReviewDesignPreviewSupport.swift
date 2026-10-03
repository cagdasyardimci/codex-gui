import AppKit
import Testing

@testable import CodexGUI

/// Replays the fixture states captured by the optional design preview script.
@MainActor
struct GitReviewDesignPreviewSupport
{
	let capture: @MainActor (
		NSView,
		String
	) throws -> Void
	private let fixture = GitReviewDesignFixture()

	func renderComparison() async throws
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
		let snapshot = try await waitForComparison(
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
		try capture(
			controller.view,
			"changes-wide.png"
		)
		resize(
			window,
			controller: controller,
			width: 760
		)
		try capture(
			controller.view,
			"changes-compact.png"
		)
		try await renderDarkComparison(presentation)

		let last = try #require(snapshot.files.last)
		_ = controller.selectFile(
			snapshotID: snapshot.id,
			fileID: last.id,
			owner: presentation.owner
		)
		let previous = try button(
			in: controller.view,
			label: "Previous changed file"
		)
		previous.performClick(nil)
		controller.view.layoutSubtreeIfNeeded()
		try capture(
			controller.view,
			"changes-selected-file.png"
		)
		resize(
			window,
			controller: controller,
			width: 420
		)
		try capture(
			controller.view,
			"changes-narrow.png"
		)

		for width: CGFloat in [1400, 420, 1400]
		{
			resize(
				window,
				controller: controller,
				width: width
			)
			try capture(
				controller.view,
				width > 500 ? "responsive-diff-wide.png" : "responsive-diff-narrow.png"
			)
		}
		let layout = try button(
			in: controller.view,
			label: "Switch diff layout"
		)
		layout.performClick(nil)
		resize(
			window,
			controller: controller,
			width: 1400
		)
		try capture(
			controller.view,
			"diff-forced-unified.png"
		)
		resize(
			window,
			controller: controller,
			width: 420
		)
		layout.performClick(nil)
		try capture(
			controller.view,
			"diff-forced-split-narrow.png"
		)
		layout.performClick(nil)
		resize(
			window,
			controller: controller,
			width: 1100
		)
		try capture(
			controller.view,
			"scope-uncommitted.png"
		)
		controller.runtime.selectScope(.branch)
		_ = try await waitForComparison(
			controller,
			owner: presentation.owner
		)
		try capture(
			controller.view,
			"scope-branch.png"
		)
		controller.runtime.selectScope(.uncommitted)
		_ = try await waitForComparison(
			controller,
			owner: presentation.owner
		)
		controller.close()
		controller.activate(owner: presentation.owner)
		_ = try await waitForComparison(
			controller,
			owner: presentation.owner
		)
		window.contentViewController = nil
		try renderFocusedHost(
			controller,
			presentation: presentation
		)
	}

	func renderPinnedSummaryActivityAndAttachments() throws
	{
		for attachments in [false, true]
		{
			let controller = InspectorViewController()
			controller.renderSummary(
				fixture.summaryPresentation(attachments: attachments),
				visible: true
			)
			let window = fixture.host(
				controller,
				size: NSSize(
					width: 320,
					height: 440
				)
			)
			defer
			{
				window.close()
			}
			let filename = attachments ? "summary-attachments.png" : "summary-activity.png"
			try capture(
				controller.view,
				filename
			)
		}
	}

	private func renderDarkComparison(_ presentation: PinnedSummaryPresentation) async throws
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
		_ = try await waitForComparison(
			controller,
			owner: presentation.owner
		)
		try capture(
			controller.view,
			"changes-dark.png"
		)
		try renderDarkUnifiedRows()
	}

	private func renderDarkUnifiedRows() throws
	{
		let controller = NSViewController()
		let surface = DesktopSurface(DesktopTheme.canvas)
		controller.view = surface
		let code = GitUnifiedCodeView(
			rows: fixture.darkUnifiedRows(),
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
		try capture(
			surface,
			"unified-rows-dark.png"
		)
	}

	private func renderFocusedHost(
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
		_ = inspector.open(ContextPanelRequest(
			owner: presentation.owner,
			destination: .changes
		))
		window.layoutIfNeeded()
		panes.split.view.layoutSubtreeIfNeeded()
		try capture(
			chrome.view,
			"changes-right-panel.png"
		)
		inspector.setGitReviewFocused(true)
		window.layoutIfNeeded()
		panes.split.view.layoutSubtreeIfNeeded()
		try capture(
			chrome.view,
			"changes-full-width-host.png"
		)
		inspector.showSummary()
	}

	private func waitForComparison(
		_ controller: GitChangesViewController,
		owner: FeaturePresentationOwner
	) async throws -> GitComparisonSnapshot
	{
		for _ in 0 ..< 100
		{
			if controller.runtime.state.pendingRequest == nil,
				controller.runtime.state.snapshot != nil,
				controller.runtime.state.owner == owner
			{
				break
			}
			await Task.yield()
		}
		controller.view.layoutSubtreeIfNeeded()
		return try #require(controller.runtime.state.snapshot)
	}

	private func button(
		in view: NSView,
		label: String
	) throws -> NSButton
	{
		try #require(fixture.descendants(view).compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.accessibilityLabel() == label
		})
	}

	private func resize(
		_ window: NSWindow,
		controller: GitChangesViewController,
		width: CGFloat
	)
	{
		window.setContentSize(NSSize(
			width: width,
			height: 760
		))
		window.layoutIfNeeded()
		controller.view.layoutSubtreeIfNeeded()
	}
}
