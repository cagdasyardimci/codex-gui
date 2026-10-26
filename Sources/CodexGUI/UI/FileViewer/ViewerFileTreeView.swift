import AppKit

@MainActor
struct ViewerFileTreePresentation
{
	let name: String
	let path: String
	let icon: NSImage?
	var secondary = false
	var accessories: [NSView] = []
	var accessibilityLabel: String?
}

/// The common native tree surface. Feature adapters supply objects and their presentation.
@MainActor
final class ViewerFileTreeView: NSOutlineView, NSOutlineViewDataSource, NSOutlineViewDelegate
{
	var rootItems: [NSObject] = []
	var children: ((NSObject) -> [NSObject])?
	var isExpandable: ((NSObject) -> Bool)?
	var presentation: ((NSObject) -> ViewerFileTreePresentation)?
	var onActivate: ((NSObject, Bool) -> Void)?
	var onContextMenu: ((NSObject) -> NSMenu?)?
	var onWillExpand: ((NSObject) -> Void)?
	var onDidExpand: ((NSObject) -> Void)?
	var onDidCollapse: ((NSObject) -> Void)?
	var onSelectionChanged: ((NSObject?) -> Void)?

	var selectedItem: NSObject?
	{
		item(atRow: selectedRow) as? NSObject
	}

	var clickedItem: NSObject?
	{
		item(atRow: clickedRow) as? NSObject
	}

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		configureTree()
	}

	required init?(coder: NSCoder)
	{
		super.init(coder: coder)
		configureTree()
	}

	private func configureTree()
	{
		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file-tree"))
		addTableColumn(column)
		outlineTableColumn = column
		headerView = nil
		ViewerFileTreeLayout.configure(self)
		indentationPerLevel = ViewerFileTreeLayout.indentation
		dataSource = self
		delegate = self
		target = self
		action = #selector(activatePreview)
		doubleAction = #selector(activateRetained)
	}

	func reloadTree()
	{
		reloadData()
	}

	func toggle(_ item: NSObject)
	{
		guard isExpandable?(item) == true
		else
		{
			return
		}
		if isItemExpanded(item)
		{
			collapseItem(item)
		}
		else
		{
			expandItem(item)
		}
	}

	private func childCount(for item: Any?) -> Int
	{
		guard let item = item as? NSObject
		else
		{
			return rootItems.count
		}
		return children?(item).count ?? 0
	}

	func outlineView(
		_ outlineView: NSOutlineView,
		numberOfChildrenOfItem item: Any?
	) -> Int
	{
		childCount(for: item)
	}

	func outlineView(
		_ outlineView: NSOutlineView,
		child index: Int,
		ofItem item: Any?
	) -> Any
	{
		guard let item = item as? NSObject
		else
		{
			return rootItems[index]
		}
		return (children?(item) ?? [])[index]
	}

	func outlineView(
		_ outlineView: NSOutlineView,
		isItemExpandable item: Any
	) -> Bool
	{
		guard let item = item as? NSObject
		else
		{
			return false
		}
		return isExpandable?(item) ?? false
	}

	func outlineView(
		_ outlineView: NSOutlineView,
		viewFor tableColumn: NSTableColumn?,
		item: Any
	) -> NSView?
	{
		guard let item = item as? NSObject, let details = presentation?(item)
		else
		{
			return nil
		}
		let cell = ViewerFileTreeRow()
		cell.configure(
			name: details.name,
			path: details.path,
			depth: max(
				0,
				level(forItem: item)
			),
			isDirectory: isExpandable?(item) ?? false,
			isExpanded: isItemExpanded(item),
			icon: details.icon,
			secondary: details.secondary,
			accessories: details.accessories,
			onToggle:
			{
				[weak self, weak item] in
				guard let item
				else
				{
					return
				}
				self?.toggle(item)
			}
		)
		cell.setAccessibilityLabel(details.accessibilityLabel ?? details.name)
		return cell
	}

	func outlineView(
		_ outlineView: NSOutlineView,
		rowViewForItem item: Any
	) -> NSTableRowView?
	{
		ViewerFileTreeSelectionRow()
	}

	func outlineViewSelectionDidChange(_ notification: Notification)
	{
		onSelectionChanged?(selectedItem)
	}

	func outlineViewItemWillExpand(_ notification: Notification)
	{
		guard let item = notification.userInfo?["NSObject"] as? NSObject
		else
		{
			return
		}
		onWillExpand?(item)
	}

	func outlineViewItemDidExpand(_ notification: Notification)
	{
		updateDisclosure(
			for: notification,
			expanded: true
		)
		if let item = notification.userInfo?["NSObject"] as? NSObject
		{
			onDidExpand?(item)
		}
	}

	func outlineViewItemDidCollapse(_ notification: Notification)
	{
		updateDisclosure(
			for: notification,
			expanded: false
		)
		if let item = notification.userInfo?["NSObject"] as? NSObject
		{
			onDidCollapse?(item)
		}
	}

	private func updateDisclosure(
		for notification: Notification,
		expanded: Bool
	)
	{
		guard let item = notification.userInfo?["NSObject"] as? NSObject
		else
		{
			return
		}
		let index = row(forItem: item)
		guard index >= 0
		else
		{
			return
		}
		let cell = view(
			atColumn: 0,
			row: index,
			makeIfNecessary: false
		)
			as? ViewerFileTreeRow
		cell?.setExpanded(expanded)
	}

	override func frameOfOutlineCell(atRow row: Int) -> NSRect
	{
		.zero
	}

	override func frameOfCell(
		atColumn column: Int,
		row: Int
	) -> NSRect
	{
		let frame = super.frameOfCell(
			atColumn: column,
			row: row
		)
		guard column == 0, row >= 0, row < numberOfRows
		else
		{
			return frame
		}
		return NSRect(
			x: 0,
			y: frame.minY,
			width: bounds.width,
			height: frame.height
		)
	}

	override func menu(for event: NSEvent) -> NSMenu?
	{
		let point = convert(
			event.locationInWindow,
			from: nil
		)
		let index = row(at: point)
		guard index >= 0, let item = item(atRow: index) as? NSObject
		else
		{
			return nil
		}
		return onContextMenu?(item)
	}

	override func keyDown(with event: NSEvent)
	{
		switch event.keyCode
		{
		case 123: navigate(expand: false)
		case 124: navigate(expand: true)
		case 36, 76: activateSelected(retained: false)
		case 49: activateSelected(retained: true)
		default: super.keyDown(with: event)
		}
	}

	private func navigate(expand: Bool)
	{
		guard let item = selectedItem
		else
		{
			return
		}
		if expand
		{
			if isExpandable?(item) == true, !isItemExpanded(item)
			{
				expandItem(item)
			}
			else if isItemExpanded(item), childCount(for: item) > 0
			{
				selectRowIndexes(
					IndexSet(integer: selectedRow + 1),
					byExtendingSelection: false
				)
			}
		}
		else if isItemExpanded(item)
		{
			collapseItem(item)
		}
		else if let parent = parent(forItem: item)
		{
			let index = row(forItem: parent)
			if index >= 0
			{
				selectRowIndexes(
					IndexSet(integer: index),
					byExtendingSelection: false
				)
			}
		}
	}

	@objc private func activatePreview()
	{
		activate(
			clickedItem ?? selectedItem,
			retained: false
		)
	}

	@objc private func activateRetained()
	{
		activate(
			clickedItem ?? selectedItem,
			retained: true
		)
	}

	private func activateSelected(retained: Bool)
	{
		activate(
			selectedItem,
			retained: retained
		)
	}

	private func activate(
		_ item: NSObject?,
		retained: Bool
	)
	{
		guard let item
		else
		{
			return
		}
		if isExpandable?(item) == true
		{
			toggle(item)
		}
		else
		{
			onActivate?(item, retained)
		}
	}
}
