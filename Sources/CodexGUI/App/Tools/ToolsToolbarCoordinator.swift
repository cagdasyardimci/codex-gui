import AppKit

/// Owns the tools button, retained-tab display, toolbar composition, and separator geometry.
@MainActor
final class ToolsToolbarCoordinator
{
	let openButton = DesktopToolbarIconButton(
		image: nil,
		label: "Open tab pane",
		preset: .contentToolbar
	)
	let closedSeparator = ToolbarSeparatorView()
	let separator = ToolbarSeparatorView(constrained: false)
	private var previousIsOpen: Bool?
	private var previousIsExpanded: Bool?
	private var tabBarWidthConstraint: NSLayoutConstraint?

	func configureTabBarItem(
		_ item: NSToolbarItem,
		paneController: WindowPaneController,
		inspector: InspectorViewController
	)
	{
		item.label = "Tabs"
		let tabBar = inspector.toolsTabs.tabBarView
		inspector.toolsTabs.setToolbarVerticalOffsets(
			tabs: LayoutTokens.NativeChrome.toolbarTabOffset,
			controls: LayoutTokens.NativeChrome.toolbarControlOffset
		)
		tabBar.clipsToBounds = false
		if tabBarWidthConstraint == nil
		{
			let width = tabBar.widthAnchor.constraint(equalToConstant: toolsTabBarWidth(
				paneController: paneController,
				inspector: inspector
			))
			width.isActive = true
			tabBarWidthConstraint = width
		}
		item.view = tabBar
		item.visibilityPriority = .high
	}

	func configureOpenButton(
		target: AnyObject,
		action: Selector
	)
	{
		openButton.target = target
		openButton.action = action
		openButton.image = openTabPaneImage()
		openButton.keyEquivalent = "b"
		openButton.keyEquivalentModifierMask = [.command, .shift]
		openButton.tooltipShortcut = "⇧⌘B"
	}

	private func toolsTabBarWidth(
		paneController: WindowPaneController,
		inspector: InspectorViewController
	) -> CGFloat
	{
		// Compensate for the native item inset and the pane's 4-point outer border.
		max(
			inspector.toolsTabs.minimumTabBarWidth,
			paneController.tabViewportWidth - LayoutTokens.NativeChrome.tabBarWidthCompensation
		)
	}

	func update(
		toolbar: NSToolbar,
		window: NSWindow?,
		paneController: WindowPaneController,
		inspector: InspectorViewController,
		defaultIdentifiers: [NSToolbarItem.Identifier],
		allowDuringExpansion: Bool
	)
	{
		guard allowDuringExpansion || !paneController.isAnimatingToolsExpansion
		else
		{
			return
		}
		let isOpen = inspector
			.isShowingTools &&
			(paneController.isToolsExpanded || !paneController.split.splitViewItems[2].isCollapsed)
		let isExpanded = paneController.isToolsExpanded
		updateOpenButton(retainedTabCount: inspector.toolsTabs.tabCount)
		updateToolbarComposition(
			isOpen: isOpen,
			isExpanded: isExpanded,
			defaultIdentifiers: defaultIdentifiers,
			toolbar: toolbar
		)
		if isOpen
		{
			inspector.toolsTabs.setPaneWidth(paneController.tabViewportWidth)
			inspector.toolsTabs.tabBarView.alphaValue = min(
				1,
				paneController.tabViewportWidth / inspector.toolsTabs.minimumTabBarWidth
			)
			let width = toolsTabBarWidth(
				paneController: paneController,
				inspector: inspector
			)
			if tabBarWidthConstraint?.constant != width
			{
				tabBarWidthConstraint?.constant = width
			}
			updateToolsToolbarSeparator(
				isExpanded: isExpanded,
				paneController: paneController,
				inspector: inspector,
				window: window
			)
		}
	}

	private func updateOpenButton(retainedTabCount: Int)
	{
		if openButton.tag != retainedTabCount
		{
			openButton.tag = retainedTabCount
			openButton.image = retainedTabCount > 0
				? retainedTabsImage(retainedTabCount) : openTabPaneImage()
		}
		let openLabel = "New tab"
		openButton.label = openLabel
	}

	private func openTabPaneImage() -> NSImage?
	{
		DesktopIcons.image(
			.plusSquareAdd,
			size: 16
		)
	}

	private func updateToolbarComposition(
		isOpen: Bool,
		isExpanded: Bool,
		defaultIdentifiers: [NSToolbarItem.Identifier],
		toolbar: NSToolbar
	)
	{
		if previousIsOpen != isOpen || previousIsExpanded != isExpanded
		{
			previousIsOpen = isOpen
			previousIsExpanded = isExpanded
			openButton.isHidden = isOpen
			closedSeparator.isHidden = isOpen
			let identifiers: [NSToolbarItem.Identifier]
			if isOpen, isExpanded
			{
				// Keep the tab bar adjacent: flexible space displaces the tracking rule.
				identifiers = [MainWindowController.ToolbarItem.navigationControls,
								MainWindowController.ToolbarItem.navigationSeparator,
								MainWindowController.ToolbarItem.toolsTabBar]
			}
			else if isOpen
			{
				identifiers = defaultIdentifiers
					+ [
						MainWindowController.ToolbarItem.toolsSeparator,
						MainWindowController.ToolbarItem.toolsTabBar
					]
			}
			else
			{
				identifiers = defaultIdentifiers
			}
			updateToolbarItems(
				identifiers,
				in: toolbar
			)
		}
	}

	private func updateToolbarItems(
		_ identifiers: [NSToolbarItem.Identifier],
		in toolbar: NSToolbar
	)
	{
		var sharedCount = 0
		while sharedCount < min(
			toolbar.items.count,
			identifiers.count
		),
			toolbar.items[sharedCount].itemIdentifier == identifiers[sharedCount]
		{
			sharedCount += 1
		}
		while toolbar.items.count > sharedCount
		{
			toolbar.removeItem(at: toolbar.items.count - 1)
		}
		for index in sharedCount ..< identifiers.count
		{
			toolbar.insertItem(
				withItemIdentifier: identifiers[index],
				at: index
			)
		}
	}

	private func updateToolsToolbarSeparator(
		isExpanded: Bool,
		paneController: WindowPaneController,
		inspector: InspectorViewController,
		window: NSWindow?
	)
	{
		let tabBar = inspector.toolsTabs.tabBarView
		guard let window, tabBar.window === window
		else
		{
			return
		}
		if separator.superview !== tabBar
		{
			tabBar.addSubview(separator)
		}
		let splitView = paneController.split.splitView
		let position = NSPoint(
			x: splitView.subviews[1].frame.maxX + splitView.dividerThickness / 2,
			y: 0
		)
		let divider = splitView.convert(
			position,
			to: tabBar
		)
		inspector.toolsTabs.alignTabsWithPaneDivider(
			at: divider.x,
			expanded: isExpanded
		)
		let frame = ToolbarSeparatorView.frame(
			dividerPosition: divider,
			hostBounds: tabBar.bounds,
			backingScale: window.backingScaleFactor
		)
		if separator.frame != frame
		{
			separator.frame = frame
		}
		separator.isHidden = isExpanded
	}

	private func retainedTabsImage(_ count: Int) -> NSImage
	{
		let image = NSImage(
			size: NSSize(
				width: 16,
				height: 16
			),
			flipped: false
		)
		{
			rect in
			NSColor.black.setStroke()
			let outline = NSBezierPath(
				roundedRect: rect.insetBy(
					dx: 2,
					dy: 2
				),
				xRadius: 2,
				yRadius: 2
			)
			outline.lineWidth = 1.2
			outline.stroke()
			let text = (count > 99 ? "99+" : String(count)) as NSString
			let attributes: [NSAttributedString.Key: Any] = [
				.font: NSFont.systemFont(ofSize: count > 99 ? 6 : 9),
				.foregroundColor: NSColor.black
			]
			let size = text.size(withAttributes: attributes)
			text.draw(
				at: NSPoint(
					x: rect.midX - size.width / 2,
					y: rect.midY - size.height / 2
				),
				withAttributes: attributes
			)
			return true
		}
		image.isTemplate = true
		return image
	}

}
