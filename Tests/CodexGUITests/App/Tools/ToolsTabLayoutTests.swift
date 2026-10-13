import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ToolsTabLayoutTests
{
	@Test func toolsTileResizesAcrossColumnsAndFullView() throws
	{
		_ = NSApplication.shared
		let controller = ToolsTabViewController()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 320,
				height: 300
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		let host = try #require(window.contentView)
		controller.view.frame = host.bounds
		host.addSubview(controller.view)
		defer
		{
			window.close()
		}
		let changes = try #require(button(
			"Changes",
			in: controller.view
		))
		let samples: [(pane: CGFloat, tile: CGFloat, leading: CGFloat)] = [
			(320, 280, 20),
			(654.8125, 299.40625, 20),
			(1214.796875, 376, 223.3984375),
			(484, 444, 20),
			(488, 216, 20),
			(320, 280, 20),
		]
		for appearance: NSAppearance.Name in [.aqua, .darkAqua]
		{
			window.appearance = NSAppearance(named: appearance)
			for sample in samples
			{
				controller.view.setFrameSize(NSSize(
					width: sample.pane,
					height: 300
				))
				window.layoutIfNeeded()
				controller.view.layoutSubtreeIfNeeded()
				let frame = changes.convert(
					changes.bounds,
					to: controller.view
				)
				#expect(abs(frame.width - sample.tile) < 0.5)
				#expect(
					abs(frame.minX - sample.leading) < 0.5,
					"Pane \(sample.pane), painted frame \(frame)"
				)
				#expect(frame.height == 40)
				#expect(changes.isEnabled)
			}
		}
	}

	@Test func addingTabsKeepsTheRightPaneAtItsChosenWidth() throws
	{
		_ = NSApplication.shared
		let suite = "ToolsTabPaneWidth.\(UUID())"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let state = WorkspaceTestFixture(storage: LocalStorage(defaults: defaults))
		let controller = MainWindowController(
			store: state.store,
			onOpenProject:
			{
			},
			onInsertPath:
			{
			}
		)
		let window = try #require(controller.window)
		defer
		{
			window.close()
		}
		window.setContentSize(NSSize(
			width: 1512,
			height: 876
		))
		let panes = controller.paneController
		panes.didPresentWindow()
		controller.inspector.showToolsPane()
		panes.setReviewCollapsed(false)
		controller.updateToolsToolbarControls()
		window.layoutIfNeeded()

		let toolbarViews = try #require(window.toolbar).items.compactMap(\.view)
		let back = try #require(toolbarViews.compactMap
		{
			button(
				"Back",
				in: $0
			)
		}.first)
		let sidebar = try #require(toolbarViews.compactMap
		{
			button(
				"Toggle sidebar",
				in: $0
			)
		}.first)
		#expect(sidebar.isEnabled)
		#expect(sidebar.target === controller)
		#expect(sidebar.action != nil)
		#expect(sidebar.bounds.size == NSSize(
			width: 28,
			height: 28
		))
		let backFrame = back.convert(
			back.bounds,
			to: nil
		)
		#expect(backFrame.height == 28)
		#expect(abs(window.frame.height - backFrame.midY - 22) < 0.5)
		let titleFrame = controller.titleLabel.convert(
			controller.titleLabel.bounds,
			to: nil
		)
		#expect(abs(window.frame.height - titleFrame.midY - 21.5) < 0.5)
		let nativeHeader = controller.inspector.toolsTabs.tabBarView
		let nativeAdd = try #require(button(
			"Add tab",
			in: nativeHeader
		))
		let tabSelection = try #require(button(
			"New tab 1",
			in: nativeHeader
		))
		#expect(tabSelection.image == nil)
		#expect(tabSelection.target === controller.inspector.toolsTabs)
		#expect(tabSelection.action != nil)
		let nativeExpand = try #require(button(
			"Expand tab pane",
			in: nativeHeader
		))
		let addFrame = nativeAdd.convert(
			nativeAdd.bounds,
			to: nil
		)
		let expandFrame = nativeExpand.convert(
			nativeExpand.bounds,
			to: nil
		)
		#expect(abs(window.frame.height - addFrame.maxY - 7.5) < 0.5)
		#expect(abs(window.frame.height - expandFrame.maxY - 8) < 0.5)
		let nativeClose = try #require(button(
			"Close tab 1",
			in: nativeHeader
		))
		let closeFrame = nativeClose.convert(
			nativeClose.bounds,
			to: nil
		)
		let nativeTab = try #require(nativeClose.superview)
		let tabFrame = nativeTab.convert(
			nativeTab.bounds,
			to: nil
		)
		#expect(abs(window.frame.height - closeFrame.maxY - 11.5) < 0.5)
		#expect(abs(window.frame.height - tabFrame.maxY - 5.5) < 0.5)
		#expect(abs(tabFrame.height - 32) < 0.5)
		window.setContentSize(NSSize(
			width: 1400,
			height: 800
		))
		window.layoutIfNeeded()

		let splitFrame = panes.split.view.convert(
			panes.split.view.bounds,
			to: nil
		)
		#expect(abs(window.frame.height - splitFrame.maxY - 43.5) < 0.5)
		#expect(window.titlebarAccessoryViewControllers.isEmpty)
		let initialWidth = panes.reviewViewportWidth
		#expect(abs(initialWidth - WindowPaneLayout.toolsMinimumWidth) < 1)
		let header = controller.inspector.toolsTabs.tabBarView
		#expect(header.window === window)
		let add = try #require(button(
			"Add tab",
			in: header
		))
		for count in 2 ... 4
		{
			add.performClick(nil)
			window.layoutIfNeeded()
			#expect(controller.inspector.toolsTabs.tabCount == count)
			#expect(abs(panes.reviewViewportWidth - initialWidth) < 1)
		}
	}

	@Test func toolbarUsesTheToolsPaneWidthForItsTabStrip() throws
	{
		_ = NSApplication.shared
		let inspector = InspectorViewController()
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
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 1200,
				height: 760
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentViewController = chrome
		defer
		{
			window.close()
		}
		panes.restoreLayout(in: window)
		panes.didPresentWindow()
		inspector.showToolsPane()
		panes.setReviewCollapsed(false)
		window.layoutIfNeeded()

		let coordinator = ToolsToolbarCoordinator()
		let item = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("toolsTabBar"))
		coordinator.configureTabBarItem(
			item,
			paneController: panes,
			inspector: inspector
		)
		let header = try #require(item.view)
		let content = try #require(window.contentView)
		header.translatesAutoresizingMaskIntoConstraints = false
		content.addSubview(header)
		NSLayoutConstraint.activate([
			header.leadingAnchor.constraint(equalTo: content.leadingAnchor),
			header.topAnchor.constraint(equalTo: content.topAnchor),
		])
		window.layoutIfNeeded()
		header.layoutSubtreeIfNeeded()

		let paneWidth = panes.reviewViewportWidth
		let scrollView = try #require(descendant(
			NSScrollView.self,
			in: header
		))
		#expect(abs(header.bounds.width - (paneWidth - 12)) < 1)
		#expect(abs(scrollView.contentView.bounds.width - min(
			238,
			paneWidth - 131
		)) <= 2)
	}

	@Test(arguments: [(320.0, 1, 197.0),
						(320.0, 2, 97.5),
						(362.0, 1, 238.0),
						(363.0, 1, 238.0),
						(506.0, 1, 238.0),
						(320.0, 3, 88.0),
						(440.0, 4, 88.0),
						(861.5, 3, 238.0),
						(861.5, 4, 183.125),
						(861.5, 5, 146.1)])
	func tabsShareAvailableWidthThenScroll(
		paneWidth: Double,
		count: Int,
		expectedTabWidth: Double
	) throws
	{
		_ = NSApplication.shared
		let tabs = ToolsTabViewController()
		let header = tabs.tabBarView
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: paneWidth,
				height: 60
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		defer
		{
			window.close()
		}
		let content = try #require(window.contentView)
		header.translatesAutoresizingMaskIntoConstraints = false
		content.addSubview(header)
		NSLayoutConstraint.activate([
			header.leadingAnchor.constraint(equalTo: content.leadingAnchor),
			header.topAnchor.constraint(equalTo: content.topAnchor),
			header.widthAnchor.constraint(equalToConstant: paneWidth - 12),
			header.heightAnchor.constraint(equalToConstant: 44),
		])
		tabs.setPaneWidth(paneWidth)
		tabs.alignTabsWithPaneDivider(
			at: -8,
			expanded: false
		)
		window.layoutIfNeeded()
		for _ in 0 ..< count
		{
			tabs.openNewTab()
		}
		header.layoutSubtreeIfNeeded()

		let scrollView = try #require(descendant(
			NSScrollView.self,
			in: header
		))
		let viewportWidth = scrollView.contentView.bounds.width
		let add = try #require(button(
			"Add tab",
			in: header
		))
		let expand = try #require(button(
			"Expand tab pane",
			in: header
		))
		let hide = try #require(button(
			"Close tab pane",
			in: header
		))
		let separator = try #require(descendant(
			ToolbarSeparatorView.self,
			in: header
		))
		let addFrame = add.convert(
			add.bounds,
			to: header
		)
		let expandFrame = expand.convert(
			expand.bounds,
			to: header
		)
		let hideFrame = hide.convert(
			hide.bounds,
			to: header
		)
		let separatorFrame = separator.convert(
			separator.bounds,
			to: header
		)
		#expect(addFrame.size == NSSize(
			width: 28,
			height: 28
		))
		#expect(add.image?.size == NSSize(
			width: 16,
			height: 16
		))
		#expect(abs(addFrame.maxX - scrollView.frame.maxX - 36) < 0.5)
		#expect(abs(header.bounds.maxY - addFrame.maxY - 7.5) < 0.5)
		#expect(abs(header.bounds.maxY - expandFrame.maxY - 8) < 0.5)
		#expect(abs(hideFrame.minX - expandFrame.maxX - 6) < 0.5)
		#expect(separatorFrame.size == NSSize(
			width: 1,
			height: 16
		))
		#expect(abs(expandFrame.minX - separatorFrame.maxX - 6) < 0.5)
		#expect(separator.alphaValue == (paneWidth <= 362 ? 1 : 0))
		if count == 1
		{
			let expectedGap = max(
				6,
				paneWidth - 355
			)
			#expect(abs(separatorFrame.minX - addFrame.maxX - expectedGap) < 0.5)
		}

		#expect(abs(header.bounds.width - (paneWidth - 12)) < 1)
		#expect(abs(viewportWidth - min(
			CGFloat(count) * 238 + CGFloat(count - 1) * 2,
			CGFloat(paneWidth) - 123
		)) <= 2)
		for index in 1 ... count
		{
			let close = try #require(button(
				"Close tab \(index)",
				in: header
			))
			let tab = try #require(close.superview)
			#expect(abs(tab.frame.width - expectedTabWidth) <= 2)
			if paneWidth == 320 && count <= 2
			{
				#expect(scrollView.documentVisibleRect.contains(tab.frame))
			}
		}
		if paneWidth == 320 && count <= 2
		{
			let document = try #require(scrollView.documentView)
			#expect(document.frame.width <= viewportWidth + 1)
			#expect(abs(scrollView.documentVisibleRect.minX) < 1)
		}
		if count >= 3 && paneWidth <= 440
		{
			let document = try #require(scrollView.documentView)
			#expect(document.frame.width > viewportWidth)
			let newestClose = try #require(button(
				"Close tab \(count)",
				in: header
			))
			let newestTab = try #require(newestClose.superview)
			#expect(scrollView.documentVisibleRect.contains(newestTab.frame))
		}
	}

	@Test(arguments: [false, true])
	func minimumToolbarWidthKeepsTabButtonsAtFullWidth(expanded: Bool) throws
	{
		_ = NSApplication.shared
		let tabs = ToolsTabViewController()
		tabs.openNewTab()
		tabs.setExpanded(expanded)
		let header = tabs.tabBarView
		let width = tabs.minimumTabBarWidth
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: width,
				height: 60
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		defer
		{
			window.close()
		}
		let content = try #require(window.contentView)
		header.translatesAutoresizingMaskIntoConstraints = false
		content.addSubview(header)
		NSLayoutConstraint.activate([
			header.leadingAnchor.constraint(equalTo: content.leadingAnchor),
			header.topAnchor.constraint(equalTo: content.topAnchor),
			header.widthAnchor.constraint(equalToConstant: width),
			header.heightAnchor.constraint(equalToConstant: 44),
		])
		window.layoutIfNeeded()
		header.layoutSubtreeIfNeeded()

		let scrollView = try #require(descendant(
			NSScrollView.self,
			in: header
		))
		let selection = try #require(button(
			"New tab 1",
			in: header
		))
		let close = try #require(button(
			"Close tab 1",
			in: header
		))
		let tab = try #require(close.superview)
		#expect(scrollView.contentView.bounds.width >= 61)
		#expect(selection.frame.width >= 24)
		#expect(close.frame.width == 20)
		#expect(selection.frame.minX >= tab.bounds.minX)
		#expect(close.frame.maxX <= tab.bounds.maxX)
	}

	@Test(arguments: [false, true])
	func dividerAlignmentYieldsToHeaderControlsDuringResize(expanded: Bool) throws
	{
		_ = NSApplication.shared
		let tabs = ToolsTabViewController()
		tabs.openNewTab()
		let header = tabs.tabBarView
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 560,
				height: 60
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		defer
		{
			window.close()
		}
		let content = try #require(window.contentView)
		header.translatesAutoresizingMaskIntoConstraints = false
		content.addSubview(header)
		let headerWidth = header.widthAnchor.constraint(equalToConstant: 560)
		NSLayoutConstraint.activate([
			header.leadingAnchor.constraint(equalTo: content.leadingAnchor),
			header.topAnchor.constraint(equalTo: content.topAnchor),
			headerWidth,
		])
		tabs.alignTabsWithPaneDivider(
			at: 210.5,
			expanded: false
		)
		// Expansion may update the controls before the toolbar realigns with the pane.
		tabs.setExpanded(expanded)
		let scrollView = try #require(descendant(
			NSScrollView.self,
			in: header
		))
		var controlLabels = ["Add tab",
								"Close tab pane",
								expanded ? "Restore split view" : "Expand tab pane"]
		if expanded
		{
			controlLabels.append("Toggle pinned summary")
		}
		let controls = try controlLabels.map
		{
			try #require(button(
				$0,
				in: header
			))
		}
		for appearance: NSAppearance.Name in [.aqua, .darkAqua, .aqua]
		{
			window.appearance = NSAppearance(named: appearance)
			tabs.alignTabsWithPaneDivider(
				at: 210.5,
				expanded: false
			)
			for width: CGFloat in [560, 207, 560, 207]
			{
				headerWidth.constant = width
				window.layoutIfNeeded()
				header.layoutSubtreeIfNeeded()
				#expect(scrollView.frame.minX >= 0)
				#expect(scrollView.frame.width >= 28)
				#expect(scrollView.frame.maxX <= header.bounds.maxX)
				for control in controls
				{
					let frame = control.convert(
						control.bounds,
						to: header
					)
					#expect(frame.width == 28)
					#expect(frame.minX >= scrollView.frame.maxX + 8)
					#expect(frame.maxX <= header.bounds.maxX)
				}
				if width == 560
				{
					#expect(abs(scrollView.frame.minX - 218.5) < 0.5)
				}
			}
			tabs.alignTabsWithPaneDivider(
				at: -40,
				expanded: false
			)
			window.layoutIfNeeded()
			header.layoutSubtreeIfNeeded()
			#expect(scrollView.frame.minX >= 0)
		}
		tabs.alignTabsWithPaneDivider(
			at: 210.5,
			expanded: expanded
		)
		window.layoutIfNeeded()
		header.layoutSubtreeIfNeeded()
		if expanded
		{
			#expect(abs(scrollView.frame.minX - LayoutTokens.Tabs.headerLeadingInset) < 0.5)
		}
	}

	private func descendant<View: NSView>(
		_ type: View.Type,
		in view: NSView
	) -> View?
	{
		if let match = view as? View
		{
			return match
		}
		return view.subviews.lazy.compactMap
		{
			descendant(
				type,
				in: $0
			)
		}.first
	}

	private func button(
		_ label: String,
		in view: NSView
	) -> NSButton?
	{
		if let button = view as? NSButton, button.accessibilityLabel() == label
		{
			return button
		}
		return view.subviews.lazy.compactMap
		{
			button(
				label,
				in: $0
			)
		}.first
	}
}
