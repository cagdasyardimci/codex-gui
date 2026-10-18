import AppKit

@MainActor
final class FileNavigatorViewController: NSViewController, NSSearchFieldDelegate
{
	var onRequestDirectory: ((FileLocation) -> Void)?
	var onOpenFile: ((FileLocation, Bool) -> Void)?
	var onFilter: ((String) -> Void)?
	var onChooseRoot: (() -> Void)?
	var onFileContextMenu: ((FileLocation) -> NSMenu?)?
	var showsFilenameResults = true
	{
		didSet
		{
			updateRows()
		}
	}
	var currentFilterQuery: String
	{
		filter
	}

	private enum Kind: Hashable
	{
		case entry, result, loading, failed, empty, noMatches, searching, searchFailure
	}

	private final class Row: NSObject
	{
		let kind: Kind
		let location: FileLocation
		var entry: FileViewerDirectoryEntry?

		init(
			kind: Kind,
			location: FileLocation,
			entry: FileViewerDirectoryEntry? = nil
		)
		{
			self.kind = kind
			self.location = location
			self.entry = entry
		}
	}

	private struct Key: Hashable
	{
		let kind: Kind
		let location: FileLocation
	}

	private enum Geometry
	{
		static let statusSize: CGFloat = 11
	}

	private let rootButton = ViewerToolbarButton(
		title: "Files",
		target: nil,
		action: nil
	)
	private let filterField = ViewerSearchField()
	private let filterStatus = NSTextField(labelWithString: "")
	private let outline = ViewerFileTreeView()
	private var navigator: ViewerFileNavigatorView!
	private var scroll: NSScrollView
	{
		navigator.scrollView
	}
	private var state = FileViewerState()
	private var cache: [Key: Row] = [:]
	private var visibleRows: [FileLocation: [Row]] = [:]
	private var rootRows: [Row] = []
	private var requestedRoot: FileLocation?
	private var pendingReveal: FileLocation?
	private var filter = ""
	private var priorExpansion: [FileLocation] = []
	private var priorSelection: FileLocation?
	private var priorScroll = NSPoint.zero
	private var lastStructureSignature = ""
	private var expansionRequests: [FileLocation: Task<Void, Never>] = [:]

	override func loadView()
	{
		let container = DesktopSurface(AppKitColorTokens.canvas)
		rootButton.cornerRadius = 9
		rootButton.image = FileViewerIcons.image(.folder)
		rootButton.imagePosition = .imageLeading
		rootButton.alignment = .left
		rootButton.lineBreakMode = .byTruncatingMiddle
		rootButton.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		rootButton.target = self
		rootButton.action = #selector(chooseRoot)
		rootButton.setAccessibilityLabel("Choose file root")

		filterField.setAccessibilityLabel("Filter file navigator")
		filterField.delegate = self
		filterStatus.font = .systemFont(ofSize: Geometry.statusSize)
		filterStatus.textColor = .secondaryLabelColor
		filterStatus.isHidden = true
		filterStatus.setAccessibilityLabel("File filter status")

		outline.setAccessibilityLabel("Workspace files")
		outline.children =
		{
			[weak self] item in
			guard let row = item as? Row
			else
			{
				return []
			}
			return self?.visibleRows[row.location] ?? []
		}
		outline.isExpandable =
		{
			item in
			guard let row = item as? Row, let entry = row.entry
			else
			{
				return false
			}
			return row.kind == .entry && entry.isDirectory && !entry.isSymbolicLink
		}
		outline.presentation =
		{
			[weak self] item in
			guard let self, let row = item as? Row
			else
			{
				return ViewerFileTreePresentation(
					name: "",
					path: "",
					icon: nil
				)
			}
			return self.presentation(for: row)
		}
		outline.onContextMenu =
		{
			[weak self] item in
			guard let self, let row = item as? Row,
					row.kind == .entry || row.kind == .result
			else
			{
				return nil
			}
			return self.onFileContextMenu?(row.location)
		}
		outline.onActivate =
		{
			[weak self] item, retained in
			guard let row = item as? Row
			else
			{
				return
			}
			self?.activate(
				row,
				retained: retained
			)
		}
		outline.onWillExpand =
		{
			[weak self] item in
			guard let row = item as? Row
			else
			{
				return
			}
			self?.requestExpandedDirectory(row)
		}
		let headerDivider = DesktopSurface(AppKitColorTokens.subtleEdge)
		let header = NSStackView(views: [rootButton, headerDivider])
		header.orientation = .vertical
		header.alignment = .width
		header.spacing = 8
		navigator = ViewerFileNavigatorView(
			filterField: filterField,
			tree: outline,
			headerView: header,
			statusView: filterStatus
		)
		navigator.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(navigator)
		NSLayoutConstraint.activate([
			navigator.topAnchor.constraint(equalTo: container.topAnchor),
			navigator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			navigator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			navigator.bottomAnchor.constraint(equalTo: container.bottomAnchor),
			rootButton.widthAnchor.constraint(equalTo: header.widthAnchor),
			rootButton.heightAnchor.constraint(equalToConstant: 28),
			headerDivider.widthAnchor.constraint(equalTo: header.widthAnchor),
			headerDivider.heightAnchor.constraint(equalToConstant: 1),
		])
		view = container
	}

	func render(_ state: FileViewerState)
	{
		_ = view
		let oldRoot = self.state.activeRoot
		let oldGeneration = self.state.generation
		self.state = state
		if oldRoot != state.activeRoot || oldGeneration != state.generation
		{
			for request in expansionRequests.values
			{
				request.cancel()
			}
			expansionRequests.removeAll()
		}
		if oldRoot != state.activeRoot
		{
			filter = ""
			filterField.stringValue = ""
			requestedRoot = nil
			cache.removeAll()
			lastStructureSignature = ""
			pendingReveal = pendingReveal?.root == state.activeRoot ? pendingReveal : nil
		}
		rootButton.title = state.activeRoot.map
		{
			URL(fileURLWithPath: $0).lastPathComponent
		} ?? "Choose folder"
		rootButton.toolTip = state.activeRoot
		updateRows()
		if let root = rootLocation, state.directoryEntries[root] == nil,
			state.directoryRequests[root] == nil, state.directoryFailures[root] == nil,
			requestedRoot != root
		{
			requestedRoot = root
			onRequestDirectory?(root)
		}
		continueReveal()
	}

	func reveal(_ location: FileLocation)
	{
		guard location.root == state.activeRoot
		else
		{
			return
		}
		if !filter.isEmpty
		{
			setFilter("")
		}
		pendingReveal = location
		continueReveal()
	}

	func directoryEntry(for location: FileLocation) -> FileViewerDirectoryEntry?
	{
		let parentPath = location.relativePath.split(separator: "/").dropLast()
			.joined(separator: "/")
		let parent = FileLocation(
			root: location.root,
			relativePath: parentPath
		)
		return state.directoryEntries[parent]?.first
		{
			$0.location == location
		}
	}

	func controlTextDidChange(_ notification: Notification)
	{
		setFilter(filterField.stringValue)
	}

	private func setFilter(_ value: String)
	{
		let next = value.trimmingCharacters(in: .whitespacesAndNewlines)
		guard next != filter
		else
		{
			return
		}
		if filter.isEmpty, !next.isEmpty
		{
			priorExpansion = expandedLocations()
			priorSelection = selectedLocation
			priorScroll = scroll.contentView.bounds.origin
		}
		filter = next
		filterField.stringValue = value
		onFilter?(next)
		updateRows()
		if next.isEmpty
		{
			restoreExpansion(priorExpansion)
			select(priorSelection)
			scroll.contentView.scroll(to: priorScroll)
			scroll.reflectScrolledClipView(scroll.contentView)
		}
	}

	private var rootLocation: FileLocation?
	{
		state.activeRoot.map
		{
			FileLocation(
				root: $0,
				relativePath: ""
			)
		}
	}

	private var selectedLocation: FileLocation?
	{
		(outline.item(atRow: outline.selectedRow) as? Row)?.location
	}

	private func row(
		_ kind: Kind,
		_ location: FileLocation,
		entry: FileViewerDirectoryEntry? = nil
	) -> Row
	{
		let key = Key(
			kind: kind,
			location: location
		)
		if let existing = cache[key]
		{
			existing.entry = entry
			return existing
		}
		let created = Row(
			kind: kind,
			location: location,
			entry: entry
		)
		cache[key] = created
		return created
	}

	private func updateRows()
	{
		guard let root = rootLocation
		else
		{
			return
		}
		let selected = selectedLocation
		let expanded = expandedLocations()
		let offset = scroll.contentView.bounds.origin
		visibleRows.removeAll()
		if !filter.isEmpty
		{
			filterStatus.stringValue = ""
			if showsFilenameResults, let page = state.filenameResults
			{
				if page.isTruncated
				{
					filterStatus.stringValue = "Showing first \(page.results.count) matches"
				}
				if page.excludedDirectoryCount > 0
				{
					if !filterStatus.stringValue.isEmpty
					{
						filterStatus.stringValue += " · "
					}
					filterStatus.stringValue +=
						"\(page.excludedDirectoryCount) generated folders skipped"
				}
				rootRows = page.results.map
				{
					row(
						.result,
						$0
					)
				}
				if rootRows.isEmpty
				{
					rootRows = [row(
						.noMatches,
						root
					)]
				}
			}
			else if showsFilenameResults, state.searchFailure != nil
			{
				rootRows = [row(
					.searchFailure,
					root
				)]
			}
			else
			{
				rootRows = [row(
					.searching,
					root
				)]
			}
		}
		else
		{
			filterStatus.stringValue = ""
			buildDirectoryRows(root)
			rootRows = visibleRows[root] ?? []
		}
		filterStatus.isHidden = filterStatus.stringValue.isEmpty
		let signature = rootRows.map
		{
			"\($0.kind):\($0.location.relativePath)"
		}
		.joined(separator: "|")
		+ visibleRows.keys.sorted
		{
			$0.relativePath < $1.relativePath
		}.map
		{
			"\($0.relativePath):\(visibleRows[$0]?.map { $0.location.relativePath }.joined() ?? "")"
		}.joined(separator: "|")
		guard signature != lastStructureSignature
		else
		{
			return
		}
		lastStructureSignature = signature
		outline.rootItems = rootRows
		outline.reloadTree()
		if filter.isEmpty
		{
			restoreExpansion(expanded)
		}
		select(selected)
		scroll.contentView.scroll(to: offset)
		scroll.reflectScrolledClipView(scroll.contentView)
	}

	private func buildDirectoryRows(_ location: FileLocation)
	{
		let entries = (state.directoryEntries[location] ?? []).sorted
		{
			$0.isDirectory == $1.isDirectory
				? $0.name.localizedStandardCompare($1.name) == .orderedAscending
				: $0.isDirectory
		}
		var rows = entries.map
		{
			row(
				.entry,
				$0.location,
				entry: $0
			)
		}
		for entry in entries where entry.isDirectory && !entry.isSymbolicLink
		{
			buildDirectoryRows(entry.location)
		}
		if state.directoryRequests[location] != nil
		{
			rows.append(row(
				.loading,
				location
			))
		}
		else if state.directoryFailures[location] != nil
		{
			rows.append(row(
				.failed,
				location
			))
		}
		else if rows.isEmpty, state.directoryEntries[location] != nil
		{
			rows.append(row(
				.empty,
				location
			))
		}
		visibleRows[location] = rows
	}

	private func expandedLocations() -> [FileLocation]
	{
		(0 ..< outline.numberOfRows).compactMap
		{
			guard let item = outline.item(atRow: $0) as? Row,
					item.kind == .entry, outline.isItemExpanded(item)
			else
			{
				return nil
			}
			return item.location
		}
	}

	private func restoreExpansion(_ locations: [FileLocation])
	{
		for location in locations.sorted(by:
			{
				$0.relativePath.count < $1.relativePath.count
			})
		{
			if let item = cache[Key(
				kind: .entry,
				location: location
			)]
			{
				outline.expandItem(item)
			}
		}
	}

	private func select(_ location: FileLocation?)
	{
		guard let location
		else
		{
			return
		}
		let item = cache[Key(
			kind: filter.isEmpty ? .entry : .result,
			location: location
		)]
		let index = item.map
		{
			outline.row(forItem: $0)
		} ?? -1
		if index >= 0
		{
			outline.selectRowIndexes(
				IndexSet(integer: index),
				byExtendingSelection: false
			)
		}
	}

	private func continueReveal()
	{
		guard let target = pendingReveal, let root = rootLocation
		else
		{
			return
		}
		var parent = root
		if state.directoryEntries[root] == nil
		{
			if state.directoryRequests[root] == nil, state.directoryFailures[root] == nil
			{
				onRequestDirectory?(root)
			}
			return
		}
		if target.relativePath.isEmpty
		{
			outline.scrollRowToVisible(0)
			pendingReveal = nil
			return
		}
		for component in target.relativePath.split(separator: "/")
		{
			guard let entry = state.directoryEntries[parent]?.first(where:
				{
					$0.name == component
				})
			else
			{
				pendingReveal = nil; return
			}
			let item = row(
				.entry,
				entry.location,
				entry: entry
			)
			if entry.location == target
			{
				select(target)
				let index = outline.row(forItem: item)
				if index >= 0
				{
					outline.scrollRowToVisible(index)
				}
				pendingReveal = nil
				return
			}
			guard entry.isDirectory, !entry.isSymbolicLink
			else
			{
				pendingReveal = nil
				return
			}
			outline.expandItem(item)
			if state.directoryEntries[entry.location] == nil
			{
				if state.directoryRequests[entry.location] == nil,
					state.directoryFailures[entry.location] == nil
				{
					onRequestDirectory?(entry.location)
				}
				return
			}
			parent = entry.location
		}
	}

	private func requestExpandedDirectory(_ item: Row)
	{
		guard item.kind == .entry, let entry = item.entry,
				state.directoryEntries[entry.location] == nil,
				state.directoryRequests[entry.location] == nil,
				state.directoryFailures[entry.location] == nil
		else
		{
			return
		}
		let location = entry.location
		guard expansionRequests[location] == nil
		else
		{
			return
		}
		let generation = state.generation
		// Directory requests synchronously publish state and reload the outline. Wait until
		// AppKit has finished expanding its item before allowing that publication.
		expansionRequests[location] = Task
		{
			@MainActor [weak self] in
			guard let self, !Task.isCancelled
			else
			{
				return
			}
			self.expansionRequests[location] = nil
			guard self.state.activeRoot == location.root,
					self.state.generation == generation,
					let item = self.cache[Key(
					kind: .entry,
					location: location
					)],
					self.outline.isItemExpanded(item),
					self.state.directoryEntries[location] == nil,
					self.state.directoryRequests[location] == nil,
					self.state.directoryFailures[location] == nil
			else
			{
				return
			}
			self.onRequestDirectory?(location)
		}
	}

	private func presentation(for row: Row) -> ViewerFileTreePresentation
	{
		ViewerFileTreePresentation(
			name: title(for: row),
			path: row.location.relativePath,
			icon: showsIcon(for: row) ? WorkspaceFileIcon.image(
				relativePath: row.location.relativePath,
				isSymbolicLink: row.entry?.isSymbolicLink == true
			) : nil,
			secondary: row.kind != .entry && row.kind != .result,
			accessibilityLabel: row.kind == .result
				? row.location.relativePath : title(for: row)
		)
	}

	private func showsIcon(for row: Row) -> Bool
	{
		(row.kind == .entry || row.kind == .result)
			&& (row.entry?.isDirectory != true || row.entry?.isSymbolicLink == true)
	}

	private func activate(
		_ row: Row,
		retained: Bool
	)
	{
		switch row.kind
		{
		case .entry:
			guard let entry = row.entry
			else
			{
				return
			}
			onOpenFile?(entry.location, retained)
		case .result: onOpenFile?(row.location, retained)
		case .failed: onRequestDirectory?(row.location)
		case .searchFailure: onFilter?(filter)
		case .loading, .empty, .noMatches, .searching: break
		}
	}

	@objc private func chooseRoot()
	{
		onChooseRoot?()
	}

	private func title(for row: Row) -> String
	{
		switch row.kind
		{
		case .entry: row.entry?.name ?? ""
		case .result: row.location.relativePath
		case .loading: "Loading…"
		case .failed: "Couldn’t load folder. Click to retry."
		case .empty: "Empty folder"
		case .noMatches: "No matching files"
		case .searching: "Searching…"
		case .searchFailure: "Search failed. Click to retry."
		}
	}
}
