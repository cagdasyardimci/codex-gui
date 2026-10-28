import AppKit

/// Context actions and skills share the same keyboard selection as project-file matches.
@MainActor
final class ComposerMentionMenu: NSViewController, NSTableViewDataSource, NSTableViewDelegate,
	DesktopPopoverSearchSuggestionsContent
{
	enum Choice
	{
		case files, search, image, code, plan, goal, project, plugins
		case skill(AvailableSkill)
		case file(String)
	}

	struct Row
	{
		let title: String
		let detail: String
		let image: NSImage?
		let choice: Choice?
		var isEnabled = true
	}

	var onChoose: ((Choice) -> Void)?
	var hasResults: Bool
	{
		!rows.isEmpty
	}
	private var rows: [Row] = []
	private let table = SlashCommandMenuTableView()
	private let scroll = NSScrollView()

	override func loadView()
	{
		table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("mention")))
		table.headerView = nil
		table.style = .plain
		table.rowHeight = LayoutTokens.SearchSuggestions.rowHeight
		table.intercellSpacing = .zero
		table.backgroundColor = .clear
		table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
		table.dataSource = self
		table.delegate = self
		table.target = self
		table.action = #selector(chooseClicked)
		table.setAccessibilityLabel("Add context")
		scroll.documentView = table
		scroll.hasVerticalScroller = true
		scroll.autohidesScrollers = true
		scroll.drawsBackground = false
		scroll.contentView.drawsBackground = false
		view = NSView()
		AppKitLayout.pin(
			scroll,
			to: view,
			inset: 0
		)
	}

	func render(
		query: String,
		skills: [AvailableSkill],
		paths: [String],
		hasProject: Bool,
		planMode: Bool,
		allowsPlanMode: Bool,
		allowsProjectSelection: Bool,
		allowsPluginManagement: Bool
	)
	{
		_ = view
		var actions = [
			Row(
				title: "Files",
				detail: "",
				image: DesktopIcons.image(.paperclip),
				choice: .files
			),
			Row(
				title: "Attach image",
				detail: "",
				image: DesktopIcons.image(.imageSquare),
				choice: .image
			)
		]
		if hasProject
		{
			actions.append(Row(
				title: "Search project files",
				detail: "",
				image: DesktopIcons.image(.search),
				choice: .search
			))
			actions.append(Row(
				title: "Code selection",
				detail: "Attach a code range",
				image: DesktopIcons.image(.code),
				choice: .code
			))
		}
		if allowsProjectSelection
		{
			actions.append(Row(
				title: "Work in a project",
				detail: "Choose a project",
				image: DesktopIcons.image(.folder),
				choice: .project
			))
		}
		actions.append(contentsOf: [
			Row(
				title: "Goal",
				detail: "Set a goal to keep pursuing",
				image: DesktopIcons.image(.flag),
				choice: .goal,
				isEnabled: false
			),
			Row(
				title: "Plan mode",
				detail: planMode ? "Turn plan mode off" : "Turn plan mode on",
				image: DesktopIcons.image(.lightbulb),
				choice: .plan,
				isEnabled: allowsPlanMode
			)
		])
		let matches: (String)
			-> Bool =
			{
				query.isEmpty || $0.localizedCaseInsensitiveContains(query)
			}
		actions = actions.filter
		{
			matches($0.title)
		}
		rows = []
		func appendSection(
			_ title: String,
			_ items: [Row]
		)
		{
			guard !items.isEmpty
			else
			{
				return
			}
			rows.append(Row(
				title: title,
				detail: "",
				image: nil,
				choice: nil
			))
			rows.append(contentsOf: items)
		}
		appendSection(
			"Add",
			actions
		)
		if allowsPluginManagement, matches("Manage plugins")
		{
			appendSection(
				"Plugins",
				[Row(
					title: "Manage plugins",
					detail: "Browse and configure plugins",
					image: DesktopIcons.image(.pluginPuzzle),
					choice: .plugins
				)]
			)
		}
		let matchingSkills = skills
			.filter
			{
				$0.enabled && matches(($0.displayName ?? $0.name) + " " + $0.description)
			}
		appendSection(
			"Skills",
			matchingSkills.map
			{
				Row(
					title: $0.displayName ?? $0.name,
					detail: $0.shortDescription ?? $0.description,
					image: NSImage(
						systemSymbolName: "shippingbox",
						accessibilityDescription: nil
					),
					choice: .skill($0)
				)
			}
		)
		if !query.isEmpty
		{
			appendSection(
				"Files",
				paths.map
				{
					Row(
						title: URL(fileURLWithPath: $0).lastPathComponent,
						detail: $0,
						image: NSImage(
							systemSymbolName: "doc",
							accessibilityDescription: nil
						),
						choice: .file($0)
					)
				}
			)
		}
		table.reloadData()
		if let first = rows.firstIndex(where:
			{
				$0.choice != nil && $0.isEnabled
			})
		{
			table.selectRowIndexes(
				IndexSet(integer: first),
				byExtendingSelection: false
			)
		}
		else
		{
			table.deselectAll(nil)
		}
		preferredContentSize = NSSize(
			width: LayoutTokens.SearchSuggestions.preferredWidth,
			height: LayoutTokens.SearchSuggestions
				.preferredHeight(rowCount: rows.count)
		)
	}

	func moveSelection(by delta: Int)
	{
		let choices = rows.indices.filter
		{
			rows[$0].choice != nil && rows[$0].isEnabled
		}
		guard !choices.isEmpty
		else
		{
			return
		}
		let current = choices.firstIndex(of: table.selectedRow) ?? 0
		let index = choices[min(
			max(
				0,
				current + delta
			),
			choices.count - 1
		)]
		table.selectRowIndexes(
			IndexSet(integer: index),
			byExtendingSelection: false
		)
		table.scrollRowToVisible(index)
	}

	@objc func chooseSelected()
	{
		guard rows.indices.contains(table.selectedRow), rows[table.selectedRow].isEnabled,
				let choice = rows[table.selectedRow].choice
		else
		{
			return
		}
		onChoose?(choice)
	}

	@objc private func chooseClicked()
	{
		let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
		guard rows.indices.contains(row), rows[row].isEnabled, let choice = rows[row].choice
		else
		{
			return
		}
		onChoose?(choice)
	}

	func numberOfRows(in tableView: NSTableView) -> Int
	{
		rows.count
	}

	func tableView(
		_ tableView: NSTableView,
		shouldSelectRow row: Int
	) -> Bool
	{
		rows[row].choice != nil && rows[row].isEnabled
	}

	func tableView(
		_ tableView: NSTableView,
		rowViewForRow row: Int
	) -> NSTableRowView?
	{
		rows[row].choice == nil ? NSTableRowView() : SlashCommandMenuRowView()
	}

	func tableView(
		_ tableView: NSTableView,
		viewFor tableColumn: NSTableColumn?,
		row: Int
	) -> NSView?
	{
		let item = rows[row]
		let cell = NSTableCellView()
		if item.choice == nil
		{
			let label = NSTextField(labelWithString: item.title)
			label.font = .systemFont(ofSize: 13)
			label.textColor = .secondaryLabelColor
			cell.addSubview(label)
			label.translatesAutoresizingMaskIntoConstraints = false
			NSLayoutConstraint.activate([
				label.leadingAnchor.constraint(
					equalTo: cell.leadingAnchor,
					constant: 8
				),
				label.trailingAnchor.constraint(
					equalTo: cell.trailingAnchor,
					constant: -8
				),
				label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
			])
		}
		else
		{
			let icon = NSImageView(image: item.image ?? NSImage())
			let contents = DesktopSearchResultContentView(presentation: .inlineCommand(
				title: item.title,
				detail: item.detail,
				leadingAccessory: icon,
				suffix: "",
				opensPicker: false,
				enabled: item.isEnabled
			))
			AppKitLayout.pin(
				contents,
				to: cell,
				inset: 0
			)
			cell.setAccessibilityEnabled(item.isEnabled)
			cell.setAccessibilityLabel(item.title + (item.detail.isEmpty ? "" : ". " + item.detail))
		}
		return cell
	}
}
