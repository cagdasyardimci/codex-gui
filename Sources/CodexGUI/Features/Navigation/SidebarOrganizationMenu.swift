import AppKit

/// Both menu surfaces share one panel so moving into a submenu preserves menu tracking.
@MainActor
final class SidebarOrganizationMenu: NSObject
{
	var onSelectOrganization: ((SidebarPreferences.Organization) -> Void)?
	var onSelectSortOrder: ((SidebarPreferences.SortOrder) -> Void)?
	private(set) var mainRows: [SidebarMenuRow] = []
	private(set) var optionRows: [SidebarMenuRow] = []
	var isShown: Bool
	{
		host.isShown
	}
	private var organization = SidebarPreferences.Organization.byProject
	private var sortOrder = SidebarPreferences.SortOrder.lastUpdated
	private var group: Int?
	private var selectedOption = 0
	private var inSubmenu = false
	private let host = DesktopPopoverHost(
		presentation: .sidebar(group: 0),
		content: NSView()
	)
	private var panel: NSPanel
	{
		host.panel
	}
	var content: DesktopPopoverRootView
	{
		host.root
	}
	private var mainSurface: DesktopPopoverSurface
	{
		host.primarySurface!
	}
	private var submenuSurface: DesktopPopoverSurface
	{
		host.submenuSurface!
	}

	override init()
	{
		super.init()
		host.onKeyDown =
		{
			[weak self] event in self?.handleKey(event.keyCode) ?? false
		}
		host.onPresentationChange =
		{
			[weak self] shown in
			if !shown
			{
				self?.onSelectOrganization = nil
				self?.onSelectSortOrder = nil
			}
		}
		mainSurface.setAccessibilityElement(true)
		mainSurface.setAccessibilityRole(.menu)
		mainSurface.setAccessibilityLabel("Sidebar options")
		submenuSurface.setAccessibilityElement(true)
		submenuSurface.setAccessibilityRole(.menu)
		submenuSurface.isHidden = true
		host.typeaheadRows =
		{
			[weak self] in
			guard let self
			else
			{
				return []
			}
			return inSubmenu ? optionRows : mainRows
		}
		host.onTypeaheadSelection =
		{
			[weak self] row in
			guard let self
			else
			{
				return
			}
			if inSubmenu, let index = optionRows.firstIndex(where:
				{
					$0 === row
				})
			{
				focusOption(index)
			}
			else if let index = mainRows.firstIndex(where:
				{
					$0 === row
				})
			{
				openSubmenu(
					index,
					focusOptions: false
				)
			}
		}

	}

	func show(
		from anchor: NSView,
		organization: SidebarPreferences.Organization,
		sortOrder: SidebarPreferences.SortOrder
	)
	{
		guard anchor.window != nil
		else
		{
			return
		}
		close()
		self.organization = organization
		self.sortOrder = sortOrder
		group = nil
		inSubmenu = false
		submenuSurface.isHidden = true
		makeMainRows()
		host.update(.sidebar(group: 0))
		host.show(from: anchor)
		reposition()
		panel.makeFirstResponder(mainRows.first)
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
		host.close()
	}

	func shouldForward(_ event: NSEvent) -> Bool
	{
		host.shouldForward(event)
	}

	private func reposition()
	{
		host.update(.sidebar(group: group ?? 0))
		host.layoutMenuRows(
			main: mainRows,
			submenu: optionRows
		)
	}
}
