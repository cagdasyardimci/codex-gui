import AppKit

extension NavigationViewController
{
	static let sidebarThreadPasteboardType = NSPasteboard.PasteboardType(
		"com.codexgui.sidebar-thread"
	)

	@objc func showSidebarMenu(_ sender: NSButton)
	{
		if sidebarMenu.isShown
		{
			sidebarMenu.close()
			return
		}
		projectActionsPopover.performClose(nil)
		projectInfoPopover.performClose(nil)
		searchPopover.close()
		sidebarMenu.show(
			from: sender,
			organization: sidebarPreferences.organization,
			sortOrder: sidebarPreferences.sortOrder
		)
		sidebarMenu.onSelectOrganization =
		{
			[weak self] in self?.setSidebarOrganization($0)
		}
		sidebarMenu.onSelectSortOrder =
		{
			[weak self] in self?.setSidebarSortOrder($0)
		}
	}

	func setSidebarOrganization(_ organization: SidebarPreferences.Organization)
	{
		sidebarPreferences.organization = organization
		filterThreads()
		if organization == .oneList
		{
			onLoadSidebarThreads?()
		}
	}

	func setSidebarSortOrder(_ order: SidebarPreferences.SortOrder)
	{
		if order == .manual && sidebarPreferences.manualThreadIDs.isEmpty
		{
			sidebarPreferences.manualThreadIDs = NavigationSidebarItemsBuilder.orderedThreads(
				sidebarThreads,
				sortOrder: .lastUpdated,
				manualThreadIDs: []
			).map(\.id)
		}
		sidebarPreferences.sortOrder = order
		filterThreads()
	}

	/// Local summaries override the global listing so current-checkout changes appear immediately.
	var sidebarThreads: [ThreadSummary]
	{
		guard sidebarPreferences.organization == .oneList
		else
		{
			return threads
		}
		var seen = Set<String>()
		return (threads + (renderedPresentation?.sidebarThreads ?? []))
			.filter
			{
				seen.insert($0.id).inserted
			}
	}

	func chooseSidebarThread(_ thread: ThreadSummary)
	{
		if threads.contains(where:
			{
				$0.id == thread.id
			})
		{
			onSelectThread?(thread.id)
		}
		else
		{
			onSelectSidebarTask?(thread)
		}
	}

	func tableView(
		_ tableView: NSTableView,
		pasteboardWriterForRow row: Int
	) -> NSPasteboardWriting?
	{
		guard canReorderSidebar, sidebarItems.indices.contains(row),
				case .thread(let thread) = sidebarItems[row]
		else
		{
			return nil
		}
		let item = NSPasteboardItem()
		item.setString(
			thread.id,
			forType: Self.sidebarThreadPasteboardType
		)
		return item
	}

	private var canReorderSidebar: Bool
	{
		sidebarPreferences.sortOrder == .manual
			&& searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}

	private func isChatInsertionRow(_ row: Int) -> Bool
	{
		guard row >= 0, row <= sidebarItems.count
		else
		{
			return false
		}
		if row < sidebarItems.count, case .thread = sidebarItems[row]
		{
			return true
		}
		if row > 0, case .thread = sidebarItems[row - 1]
		{
			return true
		}
		return false
	}

	func tableView(
		_ tableView: NSTableView,
		validateDrop info: NSDraggingInfo,
		proposedRow row: Int,
		proposedDropOperation operation: NSTableView.DropOperation
	) -> NSDragOperation
	{
		guard canReorderSidebar, info.draggingSource as? NSTableView === chatsTable,
				operation == .above, isChatInsertionRow(row)
		else
		{
			return []
		}
		return .move
	}

	func tableView(
		_ tableView: NSTableView,
		acceptDrop info: NSDraggingInfo,
		row: Int,
		dropOperation: NSTableView.DropOperation
	) -> Bool
	{
		guard info.draggingSource as? NSTableView === chatsTable, dropOperation == .above,
				let id = info.draggingPasteboard.string(forType: Self.sidebarThreadPasteboardType)
		else
		{
			return false
		}
		return moveSidebarThread(
			id,
			toRow: row
		)
	}

	/// Reorders only ordinary loaded chats; pins and project membership remain independent.
	func moveSidebarThread(
		_ id: String,
		toRow row: Int
	) -> Bool
	{
		guard canReorderSidebar, isChatInsertionRow(row), sidebarItems.contains(where:
			{
				if case .thread(let thread) = $0
				{
					return thread.id == id
				}
				return false
			})
		else
		{
			return false
		}
		var ordered = NavigationSidebarItemsBuilder.orderedThreads(
			sidebarThreads,
			sortOrder: .manual,
			manualThreadIDs: sidebarPreferences.manualThreadIDs
		).map(\.id)
		ordered.removeAll
		{
			$0 == id
		}
		let anchor: String
		let insertAfter: Bool
		if row < sidebarItems.count, case .thread(let thread) = sidebarItems[row]
		{
			anchor = thread.id
			insertAfter = false
		}
		else if row > 0, case .thread(let thread) = sidebarItems[row - 1]
		{
			anchor = thread.id
			insertAfter = true
		}
		else
		{
			return false
		}
		if anchor == id
		{
			return true
		}
		guard let index = ordered.firstIndex(of: anchor)
		else
		{
			return false
		}
		ordered.insert(
			id,
			at: index + (insertAfter ? 1 : 0)
		)
		let loadedIDs = Set(ordered)
		// Retain saved positions for other checkouts and temporarily unlisted conversations.
		var replacement = ordered.makeIterator()
		var saved = sidebarPreferences.manualThreadIDs.compactMap
		{
			loadedIDs.contains($0) ? replacement.next() : $0
		}
		saved.append(contentsOf: replacement)
		sidebarPreferences.manualThreadIDs = saved
		filterThreads()
		return true
	}
}
