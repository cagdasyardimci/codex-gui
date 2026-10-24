import AppKit

/// Both menu surfaces share one panel so moving into a submenu preserves menu tracking.
@MainActor
final class SidebarOrganizationMenu: NSObject
{
	var onSelectOrganization: ((SidebarPreferences.Organization) -> Void)?
	var onSelectSortOrder: ((SidebarPreferences.SortOrder) -> Void)?
	private(set) var mainRows: [SidebarMenuRow] = []
	private(set) var optionRows: [SidebarMenuRow] = []
	private(set) var isShown = false
	private var organization = SidebarPreferences.Organization.byProject
	private var sortOrder = SidebarPreferences.SortOrder.lastUpdated
	private var group: Int?
	private var selectedOption = 0
	private var inSubmenu = false
	private weak var anchor: NSView?
	private weak var parent: NSWindow?
	private weak var previousResponder: NSResponder?
	private var appearance: DesktopPanelAppearanceBinding?
	private var observers: [NSObjectProtocol] = []
	private var localMonitor: Any?
	private var globalMonitor: Any?
	private typealias Layout = LayoutTokens.SidebarMenu
	private let panel = SidebarMenuPanel(
		contentRect: .zero,
		styleMask: [.borderless, .nonactivatingPanel],
		backing: .buffered,
		defer: true
	)
	let content = SidebarMenuContent()
	private let mainSurface = DesktopPopoverSurface()
	private let submenuSurface = DesktopPopoverSurface()

	override init()
	{
		super.init()
		panel.isReleasedWhenClosed = false
		panel.backgroundColor = .clear
		panel.isOpaque = false
		panel.hasShadow = false
		panel.animationBehavior = .none
		panel.contentView = content
		content.addSubview(mainSurface)
		content.addSubview(submenuSurface)
		content.onOutsideClick =
		{
			[weak self] in self?.close()
		}
		mainSurface.setAccessibilityElement(true)
		mainSurface.setAccessibilityRole(.menu)
		mainSurface.setAccessibilityLabel("Sidebar options")
		submenuSurface.setAccessibilityElement(true)
		submenuSurface.setAccessibilityRole(.menu)
		submenuSurface.isHidden = true
	}

	func show(
		from anchor: NSView,
		organization: SidebarPreferences.Organization,
		sortOrder: SidebarPreferences.SortOrder
	)
	{
		guard let parent = anchor.window
		else
		{
			return
		}
		close()
		self.anchor = anchor
		self.parent = parent
		previousResponder = parent.firstResponder
		self.organization = organization
		self.sortOrder = sortOrder
		appearance = DesktopPanelAppearanceBinding(
			panel: panel,
			source: anchor
		)
		group = nil
		inSubmenu = false
		submenuSurface.isHidden = true
		makeMainRows()
		isShown = true
		reposition()
		parent.addChildWindow(
			panel,
			ordered: .above
		)
		panel.makeKeyAndOrderFront(nil)
		panel.makeFirstResponder(mainRows.first)
		installObservers(parent)
	}

	private func makeMainRows()
	{
		mainRows.forEach
		{
			$0.removeFromSuperview()
		}
		mainRows = [
			SidebarMenuRow(
				title: "Organize sidebar",
				icon: DesktopIcons.image(.sidebar),
				opensSubmenu: true
			),
			SidebarMenuRow(
				title: "Sort chats by",
				icon: SidebarMenuIcons.sort,
				opensSubmenu: true
			),
		]
		for (index, row) in mainRows.enumerated()
		{
			mainSurface.addSubview(row)
			row.onHover =
			{
				[weak self] in self?.openSubmenu(
					index,
					focusOptions: false
				)
			}
			row.onInvoke =
			{
				[weak self] in self?.openSubmenu(
					index,
					focusOptions: true
				)
			}
		}
	}

	func openSubmenu(
		_ index: Int,
		focusOptions: Bool
	)
	{
		guard mainRows.indices.contains(index)
		else
		{
			return
		}
		let changed = group != index
		group = index
		inSubmenu = focusOptions
		if changed || submenuSurface.isHidden
		{
			optionRows.forEach
			{
				$0.removeFromSuperview()
			}
			optionRows = index == 0
				? SidebarPreferences.Organization.allCases.map
				{
					SidebarMenuRow(
						title: $0.title,
						icon: $0 == .byProject ? DesktopIcons.image(.folder)
							: NSImage(
								systemSymbolName: "list.bullet",
								accessibilityDescription: nil
							),
						selected: $0 == organization
					)
				}
				: SidebarPreferences.SortOrder.allCases.map
				{
					SidebarMenuRow(
						title: $0.title,
						selected: $0 == sortOrder
					)
				}
			selectedOption = optionRows.firstIndex
			{
				$0.state == .on
			} ?? 0
			for (option, row) in optionRows.enumerated()
			{
				submenuSurface.addSubview(row)
				row.onHover =
				{
					[weak self] in self?.focusOption(option)
				}
				row.onInvoke =
				{
					[weak self] in self?.choose(option)
				}
			}
		}
		submenuSurface.isHidden = false
		submenuSurface.setAccessibilityLabel(mainRows[index].title)
		updateHighlight()
		reposition()
	}

	private func focusOption(_ index: Int)
	{
		inSubmenu = true
		selectedOption = index
		updateHighlight()
	}

	private func choose(_ index: Int)
	{
		guard let group, optionRows.indices.contains(index)
		else
		{
			return
		}
		let organizationAction = onSelectOrganization
		let sortingAction = onSelectSortOrder
		close()
		if group == 0
		{
			organizationAction?(SidebarPreferences.Organization.allCases[index])
		}
		else
		{
			sortingAction?(SidebarPreferences.SortOrder.allCases[index])
		}
	}

	private func updateHighlight()
	{
		for (index, row) in mainRows.enumerated()
		{
			row.menuHighlighted = index == group
		}
		for (index, row) in optionRows
			.enumerated()
		{
			row.menuHighlighted = inSubmenu && index == selectedOption
		}
		panel.makeFirstResponder(inSubmenu ? optionRows[selectedOption] : mainRows[group ?? 0])
	}

	@discardableResult func handleKey(_ keyCode: UInt16) -> Bool
	{
		switch keyCode
		{
		case 53: close()
		case 125, 126:
			let offset = keyCode == 125 ? 1 : -1
			if inSubmenu
			{
				selectedOption = (selectedOption + offset + 2) % 2
			}
			else
			{
				openSubmenu(
					((group ?? (offset == 1 ? 1 : 0)) + offset + 2) % 2,
					focusOptions: false
				)
			}
			updateHighlight()
		case 124: openSubmenu(
				group ?? 0,
				focusOptions: true
			)
		case 123:
			inSubmenu = false
			submenuSurface.isHidden = true
			updateHighlight()
		case 36, 76, 49:
			if inSubmenu
			{
				choose(selectedOption)
			}
			else
			{
				openSubmenu(
					group ?? 0,
					focusOptions: true
				)
			}
		case 48: close()
		default: return false
		}
		return true
	}

	func close()
	{
		dismiss(restoreFocus: true)
	}

	private func dismiss(restoreFocus: Bool)
	{
		guard isShown
		else
		{
			return
		}
		isShown = false
		if let localMonitor
		{
			NSEvent.removeMonitor(localMonitor)
		}
		if let globalMonitor
		{
			NSEvent.removeMonitor(globalMonitor)
		}
		localMonitor = nil
		globalMonitor = nil
		observers.forEach
		{
			NotificationCenter.default.removeObserver($0)
		}
		observers.removeAll()
		appearance?.invalidate()
		appearance = nil
		let shouldRestore = restoreFocus && panel.isKeyWindow && NSApp.isActive
		parent?.removeChildWindow(panel)
		panel.orderOut(nil)
		if shouldRestore, let parent, anchor?.window === parent, parent.isVisible
		{
			parent.makeKey()
			parent.makeFirstResponder(previousResponder)
		}
		anchor = nil
		parent = nil
		previousResponder = nil
		onSelectOrganization = nil
		onSelectSortOrder = nil
	}

	private func installObservers(_ parent: NSWindow)
	{
		let center = NotificationCenter.default
		for name in [NSWindow.didUpdateNotification,
						NSWindow.didMoveNotification,
						NSWindow.didResizeNotification]
		{
			observers.append(center.addObserver(
				forName: name,
				object: parent,
				queue: .main
			)
			{
				[weak self] _ in MainActor.assumeIsolated
				{
					self?.reposition()
				}
			})
		}
		for (name, object) in [(NSWindow.willCloseNotification, parent as AnyObject),
								(NSWindow.didMiniaturizeNotification, parent),
								(
								NSWindow.didResignMainNotification,
								parent
								),
								(NSApplication.didResignActiveNotification, NSApp as AnyObject)]
		{
			observers.append(center.addObserver(
				forName: name,
				object: object,
				queue: .main
			)
			{
				[weak self] _ in MainActor.assumeIsolated
				{
					self?.dismiss(restoreFocus: false)
				}
			})
		}
		localMonitor = NSEvent.addLocalMonitorForEvents(matching: [
			.leftMouseDown,
			.rightMouseDown,
			.keyDown
		])
		{
			[weak self] event in
			let forward = MainActor.assumeIsolated
			{
				self?.shouldForward(event) ?? true
			}
			return forward ? event : nil
		}
		globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
			.leftMouseDown,
			.rightMouseDown
		])
		{
			[weak self] _ in MainActor.assumeIsolated
			{
				self?.dismiss(restoreFocus: false)
			}
		}
	}

	func shouldForward(_ event: NSEvent) -> Bool
	{
		guard isShown
		else
		{
			return true
		}
		if event.type == .keyDown, event.window === panel || event.window === parent
		{
			return !handleKey(event.keyCode)
		}
		if event.type != .keyDown, event.window === parent, let anchor
		{
			let point = anchor.convert(
				event.locationInWindow,
				from: nil
			)
			if anchor.bounds.contains(point)
			{
				return true
			}
		}
		if event.type != .keyDown, event.window !== panel
		{
			dismiss(restoreFocus: false)
		}
		return true
	}

	private func reposition()
	{
		guard isShown, let anchor, let parent, anchor.window === parent,
				!anchor.isHiddenOrHasHiddenAncestor
		else
		{
			dismiss(restoreFocus: false)
			return
		}
		let rect = parent.convertToScreen(anchor.convert(
			anchor.bounds,
			to: nil
		))
		let screen = parent.screen?.visibleFrame ?? parent.frame
		let outset = Layout.shadowOutset
		let width = Layout.mainWidth + Layout.submenuGap + Layout.submenuWidth
		let height = Layout.height + Layout.rowHeight
		let x = min(
			max(
				rect.minX,
				screen.minX + 8
			),
			screen.maxX - width - 8
		)
		let top = min(
			rect.minY - 1,
			screen.maxY - 8
		)
		let y = max(
			top - height,
			screen.minY + 8
		)
		let frame = NSRect(
			x: x - outset,
			y: y - outset,
			width: width + 2 * outset,
			height: height + 2 * outset
		)
		if panel.frame != frame
		{
			panel.setFrame(
				frame,
				display: true
			)
		}
		mainSurface.frame = NSRect(
			x: outset,
			y: outset,
			width: Layout.mainWidth,
			height: Layout.height
		)
		submenuSurface.frame = NSRect(
			x: outset + Layout.mainWidth + Layout.submenuGap,
			y: outset + CGFloat(group ?? 0) * Layout.rowHeight,
			width: Layout.submenuWidth,
			height: Layout.height
		)
		for (surface, rows) in [(mainSurface, mainRows), (submenuSurface, optionRows)]
		{
			for (index, row) in rows.enumerated()
			{
				row.frame = NSRect(
					x: Layout.gutter,
					y: surface.bounds.height - Layout.gutter - CGFloat(index + 1) * Layout
						.rowHeight,
					width: surface.bounds.width - 2 * Layout.gutter,
					height: Layout.rowHeight
				)
			}
		}
	}
}

@MainActor
final class SidebarMenuContent: NSView
{
	var onOutsideClick: (() -> Void)?
	override var isFlipped: Bool
	{
		true
	}
	override func mouseDown(with event: NSEvent)
	{
		onOutsideClick?()
	}
}

@MainActor
private final class SidebarMenuPanel: NSPanel
{
	override var canBecomeKey: Bool
	{
		true
	}
	override var canBecomeMain: Bool
	{
		false
	}
}
