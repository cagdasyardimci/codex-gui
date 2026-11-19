import AppKit

// Black in template images defines the alpha mask; toolbar controls supply the displayed tint.

/// Owns the window toolbar entry point for the Tools pane.
@MainActor
final class ToolsToolbarCoordinator
{
	struct FullscreenControls
	{
		let navigation: NSView?
		let title: NSView?
		let actions: NSView?
	}

	private struct HostedItem
	{
		let item: NSToolbarItem
		let view: NSView
		let translatesAutoresizingMask: Bool
		let autoresizingMask: NSView.AutoresizingMask
	}

	private struct FullscreenPresentation
	{
		let toolbar: NSToolbar
		let wasVisible: Bool
		let items: [HostedItem]
		let controls: FullscreenControls
	}

	let openButton = DesktopToolbarIconButton(
		image: nil,
		label: "Open tab pane",
		preset: .contentToolbar
	)
	let closedSeparator = ToolbarSeparatorView()
	private var previousIsOpen: Bool?
	private var previousIsExpanded: Bool?
	private var fullscreenPresentation: FullscreenPresentation?

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

	func update(
		toolbar: NSToolbar,
		paneController: WindowPaneController,
		inspector: InspectorViewController,
		defaultIdentifiers: [NSToolbarItem.Identifier]
	) -> ToolsTabViewController?
	{
		let isOpen = inspector.isShowingTools &&
			(paneController.isToolsExpanded || !paneController.split.splitViewItems[2].isCollapsed)
		let isExpanded = isOpen && paneController.isToolsExpanded
		updateOpenButton(retainedTabCount: inspector.toolsTabs.tabCount)
		openButton.isHidden = isOpen
		closedSeparator.isHidden = isOpen
		inspector.toolsTabs.setPaneWidth(paneController.reviewViewportWidth)
		if previousIsOpen != isOpen || previousIsExpanded != isExpanded
		{
			previousIsOpen = isOpen
			previousIsExpanded = isExpanded
			restoreNativeToolbar()
			let identifiers: [NSToolbarItem.Identifier]
			if isExpanded
			{
				identifiers = [MainWindowController.ToolbarItem.navigationControls,
								MainWindowController.ToolbarItem.navigationSeparator,
								.flexibleSpace]
			}
			else if isOpen
			{
				// Flexible space passes pointer events through to full-size window content.
				identifiers = defaultIdentifiers + [
					MainWindowController.ToolbarItem.toolsSeparator,
					.flexibleSpace
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
		return isOpen ? inspector.toolsTabs : nil
	}

	func fullscreenControls(
		for toolbar: NSToolbar,
		present: Bool
	) -> FullscreenControls?
	{
		guard present
		else
		{
			restoreNativeToolbar()
			return nil
		}
		if let fullscreenPresentation, fullscreenPresentation.toolbar === toolbar
		{
			return fullscreenPresentation.controls
		}
		restoreNativeToolbar()
		let navigation = MainWindowController.ToolbarItem.navigationControls
		let title = MainWindowController.ToolbarItem.conversationTitle
		let actions = MainWindowController.ToolbarItem.trailingControls
		let identifiers = [navigation, title, actions]
		let items = toolbar.items.compactMap
		{
			item -> HostedItem? in
			guard identifiers.contains(item.itemIdentifier), let view = item.view
			else
			{
				return nil
			}
			return HostedItem(
				item: item,
				view: view,
				translatesAutoresizingMask: view.translatesAutoresizingMaskIntoConstraints,
				autoresizingMask: view.autoresizingMask
			)
		}
		let controls = FullscreenControls(
			navigation: items.first
			{
				$0.item.itemIdentifier == navigation
			}?.view,
			title: items.first
			{
				$0.item.itemIdentifier == title
			}?.view,
			actions: items.first
			{
				$0.item.itemIdentifier == actions
			}?.view
		)
		fullscreenPresentation = FullscreenPresentation(
			toolbar: toolbar,
			wasVisible: toolbar.isVisible,
			items: items,
			controls: controls
		)
		// AppKit draws a separate toolbar in macOS fullscreen.
		// Move its controls into the content row that already owns the tabs.
		toolbar.isVisible = false
		for hosted in items
		{
			hosted.item.view = nil
		}
		return controls
	}

	func restoreNativeToolbar()
	{
		guard let fullscreenPresentation
		else
		{
			return
		}
		self.fullscreenPresentation = nil
		for hosted in fullscreenPresentation.items
		{
			hosted.view.removeFromSuperview()
			hosted.view.translatesAutoresizingMaskIntoConstraints = hosted
				.translatesAutoresizingMask
			hosted.view.autoresizingMask = hosted.autoresizingMask
			hosted.item.view = hosted.view
		}
		fullscreenPresentation.toolbar.isVisible = fullscreenPresentation.wasVisible
	}

	func trailingEdge(
		of toolbar: NSToolbar,
		in window: NSWindow
	) -> CGFloat
	{
		guard toolbar.isVisible
		else
		{
			return 0
		}
		return (toolbar.visibleItems ?? []).compactMap
		{
			item -> CGFloat? in
			guard item.itemIdentifier != .flexibleSpace,
					let view = item.view, view.window === window,
					!view.isHiddenOrHasHiddenAncestor
			else
			{
				return nil
			}
			return view.convert(
				view.bounds,
				to: nil
			).maxX
		}.max() ?? 0
	}

	private func updateOpenButton(retainedTabCount: Int)
	{
		if openButton.tag != retainedTabCount
		{
			openButton.tag = retainedTabCount
			openButton.image = retainedTabCount > 0
				? retainedTabsImage(retainedTabCount) : openTabPaneImage()
		}
		let openLabel = retainedTabCount > 0 ? "Show tabs" : "New tab"
		openButton.label = openLabel
		openButton.setAccessibilityHelp(retainedTabCount > 0
			? "\(retainedTabCount) open \(retainedTabCount == 1 ? "tab" : "tabs")" : nil)
	}

	private func openTabPaneImage() -> NSImage?
	{
		DesktopIcons.image(
			.plusSquareAdd,
			size: 16
		)
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
			// Fixed native lettering keeps this template count inside its 16-point icon.
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
