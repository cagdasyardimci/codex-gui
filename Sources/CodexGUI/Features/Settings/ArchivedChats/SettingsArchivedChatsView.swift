import AppKit

/// Search and filters retain their controls while only a bounded page of grouped results changes.
@MainActor
final class SettingsArchivedChatsView: NSView, NSSearchFieldDelegate
{
	static let pageSize = 50
	var onRefresh: (() -> Void)?
	var onUnarchive: ((SettingsArchivedChat) -> Void)?
	var onDelete: ((SettingsArchivedChat) -> Void)?
	private let search = SettingsSearchField()
	private let type = SettingsChoicePicker(choices: [])
	private let project = SettingsChoicePicker(choices: [])
	private let results = AppKitLayout.verticalStack(
		[],
		spacing: 40
	)
	private let previous = DesktopActionButton(title: "Previous")
	private let next = DesktopActionButton(title: "Next")
	private let refreshButton = DesktopActionButton(
		title: "Refresh",
		presentation: .icon
	)
	private var paging: NSStackView!
	private var catalog = SettingsArchivedChatCatalog(threads: [])
	private var query = ""
	private var selectedProject: String?
	private var selectedKind: SettingsArchivedChatCatalog.Kind?
	private var sort = SettingsArchivedChatCatalog.Sort.updated
	private var page = 0
	private var busy = false
	private(set) var matchingCount = 0
	private(set) var visibleChatIDs: [String] = []

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		search.searchPrompt = "Search archived chats"
		search.usesOutline = true
		search.setAccessibilityLabel("Search archived chats")
		search.delegate = self
		search.heightAnchor.constraint(equalToConstant: 32).isActive = true
		type.menuWidth = 208
		type.leadingIcon = DesktopIcons.image(.filter)
		type.setAccessibilityLabel("Archived chat type and sort")
		type.onSelect =
		{
			[weak self] id in self?.selectFilter(id)
		}
		project.menuWidth = 260
		project.leadingIcon = DesktopIcons.image(.folder)
		project.setAccessibilityLabel("Archived chat project")
		project.onSelect =
		{
			[weak self] id in
			self?.selectedProject = id == "all" ? nil : id
			self?.page = 0
			self?.renderResults()
		}
		let toolbar = NSStackView(views: [search, type, project])
		toolbar.orientation = .horizontal
		toolbar.spacing = 8
		type.widthAnchor.constraint(equalToConstant: 144).isActive = true
		project.widthAnchor.constraint(equalToConstant: 176).isActive = true
		for control in [type, project]
		{
			control.setContentHuggingPriority(
				.defaultLow,
				for: .horizontal
			)
			control.setContentCompressionResistancePriority(
				.defaultLow,
				for: .horizontal
			)
		}
		previous.onAction =
		{
			[weak self] in self?.showPage((self?.page ?? 0) - 1)
		}
		next.onAction =
		{
			[weak self] in self?.showPage((self?.page ?? 0) + 1)
		}
		previous.setAccessibilityLabel("Previous archived chat page")
		next.setAccessibilityLabel("Next archived chat page")
		paging = NSStackView(views: [NSView(), previous, next])
		paging.spacing = 8
		refreshButton.image = NSImage(
			systemSymbolName: "arrow.clockwise",
			accessibilityDescription: "Refresh archived chats"
		)
		refreshButton.setAccessibilityLabel("Refresh archived chats")
		refreshButton.onAction =
		{
			[weak self] in self?.onRefresh?()
		}
		AppKitLayout.pin(
			SettingsPageLayout.document(
				title: "Archived chats",
				sections: [toolbar,
							results,
							paging],
				headerAccessory: refreshButton
			),
			to: self,
			inset: 0
		)
		renderResults()
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func update(
		catalog: SettingsArchivedChatCatalog,
		busy: Bool
	)
	{
		self.catalog = catalog
		self.busy = busy
		refreshButton.isEnabled = !busy
		renderResults()
	}

	func setSearch(_ text: String)
	{
		query = text
		if search.stringValue != text
		{
			search.stringValue = text
		}
		page = 0
		renderResults()
	}

	func selectFilter(_ id: String)
	{
		switch id
		{
		case "type:all": selectedKind = nil
		case "type:local": selectedKind = .local
		case "sort:updated": sort = .updated
		case "sort:created": sort = .created
		case "sort:alphabetical": sort = .alphabetical
		default: return
		}
		page = 0
		renderResults()
	}

	func showPage(_ index: Int)
	{
		page = max(
			0,
			index
		)
		renderResults()
	}

	func controlTextDidChange(_ notification: Notification)
	{
		setSearch(search.stringValue)
	}

	private func updateFilters()
	{
		let typeID = selectedKind == .local ? "type:local" : "type:all"
		type.setChoices(
			[
				.init(
					id: "type:all",
					title: "All chats",
					section: "Type",
					isSelected: selectedKind == nil
				),
				.init(
					id: "type:local",
					title: "Local",
					isSelected: selectedKind == .local
				),
				.init(
					id: "type:cloud",
					title: "Cloud",
					isEnabled: false,
					isSelected: false
				),
				.init(
					id: "sort:updated",
					title: "Updated",
					section: "Sort by",
					isSelected: sort == .updated
				),
				.init(
					id: "sort:created",
					title: "Created",
					isSelected: sort == .created
				),
				.init(
					id: "sort:alphabetical",
					title: "Alphabetical",
					isSelected: sort == .alphabetical
				),
			],
			selectedID: typeID
		)
		var projects: [SettingsChoicePicker.Choice] = [
			.init(
				id: "all",
				title: "All projects"
			)
		]
		for group in catalog.filter(sort: .alphabetical)
		{
			projects.append(.init(
				id: group.id ?? SettingsArchivedChatCatalog.noProjectID,
				title: group.title,
				icon: DesktopIcons.image(.folder)
			))
		}
		if let selectedProject, !projects.contains(where:
			{
				$0.id == selectedProject
			})
		{
			projects.append(.init(
				id: selectedProject,
				title: "Selected project (0 chats)",
				icon: DesktopIcons.image(.folder)
			))
		}
		project.setChoices(
			projects,
			selectedID: selectedProject ?? "all"
		)
	}

	private func renderResults()
	{
		updateFilters()
		let groups = catalog.filter(
			query: query,
			projectID: selectedProject,
			kind: selectedKind,
			sort: sort
		)
		matchingCount = groups.reduce(0)
		{
			$0 + $1.chats.count
		}
		let pages = max(
			1,
			(matchingCount + Self.pageSize - 1) / Self.pageSize
		)
		page = min(
			page,
			pages - 1
		)
		var skip = page * Self.pageSize
		var remaining = Self.pageSize
		visibleChatIDs = []
		for child in results.arrangedSubviews
		{
			results.removeArrangedSubview(child)
			child.removeFromSuperview()
		}
		for group in groups
		{
			if skip >= group.chats.count
			{
				skip -= group.chats.count; continue
			}
			let visible = Array(group.chats.dropFirst(skip).prefix(remaining))
			skip = 0
			remaining -= visible.count
			guard !visible.isEmpty
			else
			{
				break
			}
			visibleChatIDs += visible.map(\.id)
			let header = NSStackView(views: [
				NSImageView(image: DesktopIcons.image(.folder)),
				DesktopLineBoxLabel(
					group.title,
					role: TypographyTokens.Connections.section
				),
				NSView(),
			])
			header.spacing = 8
			header.heightAnchor.constraint(equalToConstant: 46).isActive = true
			let section = AppKitLayout.verticalStack(
				[
					header,
					SettingsPageLayout.card(rows: visible.map(makeRow))
				],
				spacing: 0
			)
			for child in section.arrangedSubviews
			{
				child.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
			}
			results.addArrangedSubview(section)
			section.widthAnchor.constraint(equalTo: results.widthAnchor).isActive = true
			if remaining == 0
			{
				break
			}
		}
		paging.isHidden = pages <= 1
		previous.isEnabled = page > 0
		next.isEnabled = page + 1 < pages
	}

	private func makeRow(_ chat: SettingsArchivedChat) -> NSView
	{
		let date = (sort == .created ? chat.createdAt ?? chat.updatedAt
			: chat.updatedAt ?? chat.createdAt)?.formatted(
			date: .abbreviated,
			time: .shortened
		)
		return SettingsArchivedChatRow(
			title: chat.title,
			date: date ?? "",
			isEnabled: !busy,
			onUnarchive:
			{
				[weak self] in self?.onUnarchive?(chat)
			},
			onDelete:
			{
				[weak self] in self?.onDelete?(chat)
			}
		)
	}

}
