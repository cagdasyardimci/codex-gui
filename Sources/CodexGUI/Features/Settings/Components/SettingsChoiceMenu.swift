import AppKit

/// Shared settings choice menu with hover navigation and a trailing selection check.
@MainActor
final class SettingsChoiceMenu
{
	var onClose: (() -> Void)?
	var onSelect: ((String) -> Void)?
	var onToggle: ((String, Bool) -> Void)?
	private(set) var checkedIDs: Set<String>?
	var isShown: Bool
	{
		host.isShown
	}

	private let host: DesktopPopoverHost
	private var panel: NSPanel
	{
		host.panel
	}
	private var surface: DesktopPopoverSurface
	{
		host.primarySurface!
	}
	private let scroll = NSScrollView()
	private var contentHeight: CGFloat = 8
	private var rowHeights: [CGFloat] = []
	private var sizeUpdateTask: Task<Void, Never>?
	private let choices: [SettingsChoicePicker.Choice]
	private var rows: [SettingsChoiceMenuRow] = []
	private var selectedIndex = 0
	private let menuWidth: CGFloat

	init(
		choices: [SettingsChoicePicker.Choice],
		selectedID: String?,
		accessibilityLabel: String,
		width: CGFloat = 240,
		checkedIDs: Set<String>? = nil,
		showsCheckboxes: Bool = true,
		titleRole: TypographyTokens.Role = TypographyTokens.MenuRow.title,
		detailRole: TypographyTokens.Role = TypographyTokens.MenuRow.subtitle
	)
	{
		self.checkedIDs = checkedIDs
		self.menuWidth = width
		self.choices = choices
		selectedIndex = choices.firstIndex
		{
			$0.id == selectedID && $0.isEnabled
		} ?? choices.firstIndex(where: \.isEnabled) ?? 0
		host = DesktopPopoverHost(
			presentation: .choice(
				width: width,
				contentHeight: 0
			),
			content: scroll
		)
		let stack = AppKitLayout.verticalStack(
			[],
			spacing: 0
		)
		var currentSection: String?
		for (index, choice) in choices.enumerated()
		{
			if let section = choice.section, section != currentSection
			{
				if index > 0
				{
					let separator = Self.separator()
					stack.addArrangedSubview(separator)
					separator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
					contentHeight += 9
				}
				let header = Self.sectionHeader(section)
				stack.addArrangedSubview(header)
				header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
				contentHeight += 24
				currentSection = section
			}
			let row = SettingsChoiceMenuRow(
				title: choice.title,
				icon: choice.icon,
				checked: checkedIDs?.contains(choice.id)
					?? choice.isSelected ?? (choice.id == selectedID),
				detail: choice.detail,
				showsCheckbox: checkedIDs != nil && showsCheckboxes,
				titleRole: titleRole,
				detailRole: detailRole
			)
			row.isEnabled = choice.isEnabled
			row.toolTip = choice.help
			row.setAccessibilityHelp(choice.help ?? choice.detail)
			row.onHover =
			{
				[weak self] in self?.highlight(index)
			}
			row.onChoose =
			{
				[weak self] in self?.choose(index)
			}
			stack.addArrangedSubview(row)
			row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
			rows.append(row)
			rowHeights.append(row.rowHeight)
			contentHeight += row.rowHeight
			row.onPreferredSizeChanged =
			{
				[weak self, weak row] in
				guard let self, let row
				else
				{
					return
				}
				let height = row.rowHeight
				let delta = height - self.rowHeights[index]
				self.rowHeights[index] = height
				self.contentHeight += delta
				if delta != 0
				{
					self.scheduleSizeUpdate()
				}
			}
		}
		scroll.hasVerticalScroller = true
		scroll.autohidesScrollers = true
		scroll.scrollerStyle = .overlay
		scroll.drawsBackground = false
		scroll.contentView.drawsBackground = false
		scroll.borderType = .noBorder
		let document = DesktopFlippedView()
		document.translatesAutoresizingMaskIntoConstraints = false
		scroll.documentView = document
		AppKitLayout.pin(
			stack,
			to: document,
			inset: 0
		)
		document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
		surface.setAccessibilityRole(.menu)
		surface.setAccessibilityLabel(accessibilityLabel)
		host.typeaheadRows =
		{
			[weak self] in self?.rows ?? []
		}
		host.onTypeaheadSelection =
		{
			[weak self] row in
			guard let self, let index = rows.firstIndex(where:
				{
					$0 === row
				})
			else
			{
				return
			}
			highlight(index)
		}

		host.onPresentationChange =
		{
			[weak self] shown in
			guard let self, !shown
			else
			{
				return
			}
			self.sizeUpdateTask?.cancel()
			self.sizeUpdateTask = nil
			self.onClose?()
		}

	}

	func show(from anchor: NSView)
	{
		guard !rows.isEmpty, anchor.window != nil
		else
		{
			return
		}
		for row in rows
		{
			row.menuHighlighted = false
		}
		refreshSize()
		host.onKeyDown =
		{
			[weak self] event in self?.handleKey(event.keyCode) ?? false
		}
		host.show(from: anchor)
		if rows[selectedIndex].isEnabled
		{
			panel.makeFirstResponder(rows[selectedIndex])
			rows[selectedIndex].scrollToVisible(rows[selectedIndex].bounds)
		}
	}

	isolated deinit
	{
		sizeUpdateTask?.cancel()
		// AppKit can retain ordered-out panels. Retiring the menu must release its row observers.
		host.panel.contentView = nil
		host.panel.close()
	}

	private func scheduleSizeUpdate()
	{
		guard isShown, sizeUpdateTask == nil
		else
		{
			return
		}
		sizeUpdateTask = Task
		{
			@MainActor [weak self] in
			guard let self, !Task.isCancelled
			else
			{
				return
			}
			self.sizeUpdateTask = nil
			if self.isShown
			{
				self.refreshSize()
			}
		}
	}

	private func refreshSize()
	{
		host.update(.choice(
			width: menuWidth,
			contentHeight: contentHeight
		))
	}

	func close(restoreFocus: Bool = true)
	{
		host.dismiss(restoreFocus: restoreFocus)
	}

	private func highlight(_ index: Int)
	{
		guard choices.indices.contains(index), choices[index].isEnabled
		else
		{
			return
		}
		selectedIndex = index
		DesktopMenuNavigation.highlight(
			index,
			rows: rows,
			in: panel
		)
	}

	func updateChecks(_ checkedIDs: Set<String>)
	{
		guard self.checkedIDs != nil
		else
		{
			return
		}
		self.checkedIDs = checkedIDs
		for (choice, row) in zip(
			choices,
			rows
		)
		{
			row.checked = checkedIDs.contains(choice.id)
		}
	}

	private func choose(_ index: Int)
	{
		guard choices.indices.contains(index), choices[index].isEnabled
		else
		{
			return
		}
		let choice = choices[index]
		if var checks = checkedIDs
		{
			let checked = !checks.contains(choice.id)
			if checked
			{
				checks.insert(choice.id)
			}
			else
			{
				checks.remove(choice.id)
			}
			updateChecks(checks)
			onToggle?(choice.id, checked)
		}
		else
		{
			close()
			onSelect?(choice.id)
		}
	}

	private func handleKey(_ keyCode: UInt16) -> Bool
	{
		switch keyCode
		{
		case 53, 48: close()
		case 125, 126, 36, 76:
			_ = DesktopMenuNavigation.handleKey(
				keyCode,
				rows: rows,
				currentIndex: selectedIndex,
				onHighlight: highlight,
				onChoose:
				{
					index in
					choose(index)
					return true
				}
			)
		case 49: choose(selectedIndex)
		default: return false
		}
		return true
	}

	private static func sectionHeader(_ title: String) -> NSView
	{
		let header = NSView()
		let label = NSTextField(labelWithString: title)
		label.identifier = NSUserInterfaceItemIdentifier("settings-menu-section-heading")
		label.setAccessibilityRole(.staticText)
		label.setAccessibilityRoleDescription("heading")
		label.setTypographyRole(TypographyTokens.Settings.choiceSection)
		label.textColor = AppKitColorTokens.settingsSecondaryText
		label.translatesAutoresizingMaskIntoConstraints = false
		header.addSubview(label)
		NSLayoutConstraint.activate([
			header.heightAnchor.constraint(equalToConstant: 24),
			label.leadingAnchor.constraint(
				equalTo: header.leadingAnchor,
				constant: 8
			),
			label.trailingAnchor.constraint(
				lessThanOrEqualTo: header.trailingAnchor,
				constant: -8
			),
			label.centerYAnchor.constraint(equalTo: header.centerYAnchor),
		])
		return header
	}

	private static func separator() -> NSView
	{
		let row = NSView()
		let line = SettingsSurfaceView(color: AppKitColorTokens.settingsSelectorEdge)
		line.translatesAutoresizingMaskIntoConstraints = false
		row.addSubview(line)
		NSLayoutConstraint.activate([
			row.heightAnchor.constraint(equalToConstant: 9),
			line.heightAnchor.constraint(equalToConstant: 1),
			line.centerYAnchor.constraint(equalTo: row.centerYAnchor),
			line.leadingAnchor.constraint(
				equalTo: row.leadingAnchor,
				constant: 8
			),
			line.trailingAnchor.constraint(
				equalTo: row.trailingAnchor,
				constant: -8
			),
		])
		return row
	}

}
