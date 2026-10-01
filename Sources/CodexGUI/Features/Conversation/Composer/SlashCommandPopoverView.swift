import AppKit

/// A native list whose selection stays separate from the composer's insertion point.
@MainActor
final class SlashCommandPopoverView: NSViewController, NSTableViewDataSource, NSTableViewDelegate
{
	var onChooseSkill: ((AvailableSkill) -> Void)?
	var availableSkills: [AvailableSkill] = []
	private(set) var matchingSkills: [AvailableSkill] = []
	var selectedSkill: AvailableSkill?
	{
		let index = table.selectedRow - commands.count - 1
		return matchingSkills.indices.contains(index) ? matchingSkills[index] : nil
	}
	private var rowCount: Int
	{
		commands.count + (matchingSkills.isEmpty ? 0 : matchingSkills.count + 1)
	}
	var onChoose: ((SlashCommandDescriptor) -> Void)?
	var unavailableReason: ((SlashCommandID) -> String?)?
	private let table = SlashCommandMenuTableView()
	private let scroll = NSScrollView()
	private let emptyLabel = NSTextField(labelWithString: "No matching commands or skills")
	private(set) var commands: [SlashCommandDescriptor] = []
	var selectedCommand: SlashCommandDescriptor?
	{
		commands.indices.contains(table.selectedRow) ? commands[table.selectedRow] : nil
	}

	override func loadView()
	{
		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("slashCommand"))
		table.addTableColumn(column)
		table.headerView = nil
		table.style = .plain
		table.rowHeight = 28
		table.intercellSpacing = .zero
		table.backgroundColor = .clear
		table.selectionHighlightStyle = .regular
		table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
		table.dataSource = self
		table.delegate = self
		table.target = self
		table.action = #selector(chooseSelected)
		table.setAccessibilityLabel("Slash commands. Use arrow keys to select, Tab to insert, "
			+ "Return to run, Escape to dismiss.")
		scroll.documentView = table
		scroll.hasVerticalScroller = true
		scroll.autohidesScrollers = true
		scroll.scrollerStyle = .overlay
		scroll.drawsBackground = false
		scroll.contentView.drawsBackground = false
		emptyLabel.textColor = .secondaryLabelColor
		let stack = AppKitLayout.verticalStack(
			[scroll, emptyLabel],
			spacing: 4
		)
		let container = DesktopSurface(
			DesktopTheme.slashMenu,
			cornerRadius: 22,
			bordered: true
		)
		AppKitLayout.pin(
			stack,
			to: container,
			inset: 4
		)
		scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		view = container
		preferredContentSize = NSSize(
			width: 720,
			height: 316
		)
	}

	func render(prefix: String)
	{
		_ = view
		let previousCommandID = selectedCommand?.id
		let previousSkillPath = selectedSkill?.path
		commands = SlashCommandRegistry.matching(prefix: prefix)
		matchingSkills = skillsMatching(prefix: prefix)

		let height = CGFloat(min(
			11,
			max(
				1,
				rowCount
			)
		)) * table.rowHeight
		scroll.isHidden = rowCount == 0
		preferredContentSize.height = height + 8
		table.reloadData()
		emptyLabel.isHidden = rowCount > 0
		guard rowCount > 0
		else
		{
			table.deselectAll(nil)
			return
		}
		if let index = matchingSkills.firstIndex(where:
			{
				$0.path == previousSkillPath
			})
		{
			selectRow(commands.count + 1 + index)
		}
		else
		{
			selectRow(commands.firstIndex(where:
				{
					$0.id == previousCommandID
				})
				?? (commands.isEmpty ? 1 : 0))
		}
	}

	private func skillsMatching(prefix: String) -> [AvailableSkill]
	{
		let matchingSkills = availableSkills.filter
		{
			skill in
			let matchesName = skill.name.lowercased().hasPrefix(prefix.lowercased())
			let matchesDisplayName =
				skill.displayName?.lowercased().hasPrefix(prefix.lowercased()) ?? false
			let matchesPrefix = prefix.isEmpty || matchesName || matchesDisplayName
			return skill.enabled && matchesPrefix
		}
		return matchingSkills.sorted
		{
			($0.displayName ?? $0.name).localizedStandardCompare($1.displayName ?? $1.name)
				== .orderedAscending
		}
	}

	func moveSelection(by delta: Int)
	{
		guard rowCount > 0
		else
		{
			return
		}
		var index = table.selectedRow + delta
		if !matchingSkills.isEmpty && index == commands.count
		{
			index += delta > 0 ? 1 : -1
		}
		selectRow(min(
			max(
				commands.isEmpty ? 1 : 0,
				index
			),
			rowCount - 1
		))
	}

	private func selectRow(_ index: Int)
	{
		table.selectRowIndexes(
			IndexSet(integer: index),
			byExtendingSelection: false
		)
		table.scrollRowToVisible(index)
		NSAccessibility.post(
			element: table,
			notification: .selectedRowsChanged
		)
	}

	func numberOfRows(in tableView: NSTableView) -> Int
	{
		rowCount
	}

	func tableView(
		_ tableView: NSTableView,
		viewFor tableColumn: NSTableColumn?,
		row: Int
	) -> NSView?
	{
		if !matchingSkills.isEmpty && row == commands.count
		{
			let heading = NSTextField(labelWithString: "Skills")
			heading.font = .systemFont(ofSize: 12)
			heading.textColor = .secondaryLabelColor
			let cell = NSTableCellView()
			AppKitLayout.pin(
				heading,
				to: cell,
				inset: 8
			)
			return cell
		}
		if row > commands.count
		{
			let index = row - commands.count - 1
			guard matchingSkills.indices.contains(index)
			else
			{
				return nil
			}
			return skillCell(matchingSkills[index])
		}
		guard commands.indices.contains(row)
		else
		{
			return nil
		}
		return commandCell(commands[row])
	}

	private func commandCell(_ command: SlashCommandDescriptor) -> NSView
	{
		let reason = unavailableReason?(command.id)
		let presentation = SlashCommandMenuPresentation(command.id)
		let title = makeCommandTitleLabel(
			presentation.title,
			isAvailable: reason == nil
		)
		let detail = makeDescriptionLabel(command.description)
		let icon = makeRowIcon(symbol: presentation.symbol)

		let contents = AppKitLayout.horizontalStack(
			[icon, title, detail],
			spacing: 8
		)
		if presentation.opensPicker
		{
			let chevron = makePickerChevron()
			contents.addArrangedSubview(chevron)
		}
		contents.distribution = .fill
		let cell = makeInlineCell(contents: contents)
		cell.toolTip = reason ?? command.description
		cell.setAccessibilityLabel("/\(command.name). \(command.description)"
			+ (reason.map
			{
				". " + $0
			} ?? ""))
		return cell
	}

	func tableView(
		_ tableView: NSTableView,
		didAdd rowView: NSTableRowView,
		forRow row: Int
	)
	{
		(rowView as? SlashCommandMenuRowView)?.isHovered = table.hoveredRow == row
	}

	func tableView(
		_ tableView: NSTableView,
		didRemove rowView: NSTableRowView,
		forRow row: Int
	)
	{
		(rowView as? SlashCommandMenuRowView)?.isHovered = false
	}

	func tableView(
		_ tableView: NSTableView,
		rowViewForRow row: Int
	) -> NSTableRowView?
	{
		if !matchingSkills.isEmpty && row == commands.count
		{
			return NSTableRowView()
		}
		return SlashCommandMenuRowView()
	}

	func tableView(
		_ tableView: NSTableView,
		shouldSelectRow row: Int
	) -> Bool
	{
		matchingSkills.isEmpty || row != commands.count
	}

	private func skillCell(_ skill: AvailableSkill) -> NSView
	{
		let icon = makeRowIcon(symbol: "shippingbox")
		let title = makeSkillTitleLabel(skill.displayName ?? skill.name)
		let detail = makeDescriptionLabel(skill.shortDescription ?? skill.description)
		let scope = makeSkillScopeLabel(skill.scope)
		let contents = AppKitLayout.horizontalStack(
			[icon, title, detail, scope],
			spacing: 8
		)
		contents.distribution = .fill
		let cell = makeInlineCell(contents: contents)
		cell.toolTip = skill.description
		cell.setAccessibilityLabel(
			"Skill \(skill.name). \(skill.description). \(scope.stringValue)"
		)
		return cell
	}

	private func makeCommandTitleLabel(
		_ text: String,
		isAvailable: Bool
	) -> NSTextField
	{
		let title = NSTextField(labelWithString: text)
		title.font = .systemFont(ofSize: 13)
		title.textColor = isAvailable ? .labelColor : .secondaryLabelColor
		title.setContentCompressionResistancePriority(
			.required,
			for: .horizontal
		)
		return title
	}

	private func makeSkillTitleLabel(_ text: String) -> NSTextField
	{
		let title = NSTextField(labelWithString: text)
		title.font = .systemFont(ofSize: 13)
		title.lineBreakMode = .byTruncatingTail
		return title
	}

	private func makeDescriptionLabel(_ text: String) -> NSTextField
	{
		let detail = NSTextField(labelWithString: text)
		detail.font = .systemFont(ofSize: 13)
		detail.textColor = .tertiaryLabelColor
		detail.lineBreakMode = .byTruncatingTail
		detail.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		detail.setContentHuggingPriority(
			.defaultLow,
			for: .horizontal
		)
		return detail
	}

	private func makeRowIcon(symbol: String) -> NSImageView
	{
		let icon = NSImageView()
		icon.image = NSImage(
			systemSymbolName: symbol,
			accessibilityDescription: nil
		)
		icon.contentTintColor = .secondaryLabelColor
		icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
		icon.heightAnchor.constraint(equalToConstant: 16).isActive = true
		return icon
	}

	private func makePickerChevron() -> NSImageView
	{
		let chevron = NSImageView()
		chevron.image = NSImage(
			systemSymbolName: "chevron.right",
			accessibilityDescription: nil
		)
		chevron.contentTintColor = .tertiaryLabelColor
		chevron.widthAnchor.constraint(equalToConstant: 10).isActive = true
		chevron.heightAnchor.constraint(equalToConstant: 12).isActive = true
		return chevron
	}

	private func makeSkillScopeLabel(_ scopeName: String) -> NSTextField
	{
		let scope = NSTextField(labelWithString: scopeName == "user" ? "Personal"
			: scopeName.capitalized)
		scope.font = .systemFont(ofSize: 12)
		scope.textColor = .secondaryLabelColor
		scope.setContentCompressionResistancePriority(
			.required,
			for: .horizontal
		)
		return scope
	}

	private func makeInlineCell(contents: NSStackView) -> NSTableCellView
	{
		let horizontalInset: CGFloat = 10
		let cell = NSTableCellView()
		cell.addSubview(contents)
		contents.translatesAutoresizingMaskIntoConstraints = false

		NSLayoutConstraint.activate([
			contents.leadingAnchor.constraint(
				equalTo: cell.leadingAnchor,
				constant: horizontalInset
			),
			contents.trailingAnchor.constraint(
				equalTo: cell.trailingAnchor,
				constant: -horizontalInset
			),
			contents.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
		])
		return cell
	}

	@objc private func chooseSelected()
	{
		if let selectedCommand
		{
			onChoose?(selectedCommand)
		}
		else if let selectedSkill
		{
			onChooseSkill?(selectedSkill)
		}
	}
}
