import AppKit

/// Shared reading column, cards and rows for the native settings pages.
@MainActor
enum SettingsPageLayout
{
	enum ColumnWidth
	{
		case fixed, fitsViewport
	}

	static func document(
		title: String,
		sections: [NSView],
		headerAccessory: NSView? = nil,
		subtitle: String? = nil,
		subtitleView: NSView? = nil,
		headerSpacing: SettingsPageDocument.HeaderSpacing = .standard,
		columnWidth: ColumnWidth = .fixed
	) -> SettingsPageDocument
	{
		SettingsPageDocument(
			title: title,
			sections: sections,
			headerAccessory: headerAccessory,
			subtitle: subtitle,
			subtitleView: subtitleView,
			headerSpacing: headerSpacing,
			columnWidth: columnWidth
		)
	}

	/// Keeps an existing page stack's spacing and width policy while sharing its scroll shell.
	static func document(
		content stack: NSStackView,
		columnWidth: ColumnWidth = .fixed
	) -> NSView
	{
		let container = NSView()
		AppKitLayout.pin(
			scrollableDocument(
				content: stack,
				columnWidth: columnWidth
			),
			to: container,
			inset: 0
		)
		return container
	}

	static func scrollableDocument(
		content stack: NSStackView,
		columnWidth: ColumnWidth = .fixed
	) -> NSScrollView
	{
		let scroll = NSScrollView()
		scroll.hasVerticalScroller = true
		scroll.autohidesScrollers = true
		scroll.drawsBackground = false
		scroll.contentView.drawsBackground = false
		let document = DesktopFlippedView()
		document.translatesAutoresizingMaskIntoConstraints = false
		scroll.documentView = document
		stack.translatesAutoresizingMaskIntoConstraints = false
		document.addSubview(stack)
		NSLayoutConstraint.activate([
			document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
			stack.centerXAnchor.constraint(equalTo: document.centerXAnchor),
			stack.widthAnchor
				.constraint(lessThanOrEqualToConstant: LayoutTokens.Connections.contentWidth),
			stack.leadingAnchor.constraint(
				greaterThanOrEqualTo: document.leadingAnchor,
				constant: 20
			),
			stack.trailingAnchor.constraint(
				lessThanOrEqualTo: document.trailingAnchor,
				constant: -20
			),
			stack.topAnchor.constraint(
				equalTo: document.topAnchor,
				constant: LayoutTokens.Connections.topInset
			),
			stack.bottomAnchor.constraint(
				equalTo: document.bottomAnchor,
				constant: -60
			),
		])
		let preferredWidth: NSLayoutConstraint
		switch columnWidth
		{
		case .fixed:
			preferredWidth = stack.widthAnchor.constraint(
				equalToConstant: LayoutTokens.Connections.contentWidth
			)
		case .fitsViewport:
			preferredWidth = stack.widthAnchor.constraint(
				equalTo: document.widthAnchor,
				constant: -40
			)
			preferredWidth.priority = NSLayoutConstraint.Priority(
				rawValue: NSLayoutConstraint.Priority.windowSizeStayPut.rawValue - 1
			)
		}
		preferredWidth.isActive = true
		return scroll
	}

	static func status(
		_ text: String,
		actions: [DesktopStatusView.Action] = []
	) -> DesktopStatusView
	{
		DesktopStatusView(
			message: text,
			actions: actions,
			presentation: .inline
		)
	}

	static func message(_ text: String) -> NSTextField
	{
		let label = SettingsMessageLabel(wrappingLabelWithString: text)
		label.font = AppKitFontResolver.font(TypographyTokens.Connections.caption)
		label.textColor = AppKitColorTokens.settingsSecondaryText
		label.isSelectable = true
		label.isHidden = text.isEmpty
		return label
	}

	static func section(
		title: String,
		rows: [NSView]
	) -> NSView
	{
		section(
			title: title,
			content: card(rows: rows)
		)
	}

	static func section(
		title: String,
		content: NSView
	) -> NSView
	{
		let stack = AppKitLayout.verticalStack(
			[sectionHeader(title), content],
			spacing: 0
		)
		stack.arrangedSubviews[0].widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		content.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		return stack
	}

	static func card(
		rows: [NSView]
	) -> NSView
	{
		let card = RemoteConnectionsCard()
		let contents = AppKitLayout.verticalStack(
			rows,
			spacing: 0
		)
		AppKitLayout.pin(
			contents,
			to: card,
			inset: 1
		)
		for row in rows
		{
			row.widthAnchor.constraint(equalTo: contents.widthAnchor).isActive = true
		}
		for row in rows.dropLast()
		{
			addDivider(to: row)
		}
		return card
	}

	static func addDivider(to row: NSView)
	{
		let divider = SettingsSurfaceView(color: AppKitColorTokens.connectionsEdge)
		divider.translatesAutoresizingMaskIntoConstraints = false
		row.addSubview(divider)
		NSLayoutConstraint.activate([
			divider.leadingAnchor.constraint(
				equalTo: row.leadingAnchor,
				constant: 16
			),
			divider.trailingAnchor.constraint(
				equalTo: row.trailingAnchor,
				constant: -16
			),
			divider.bottomAnchor.constraint(equalTo: row.bottomAnchor),
			divider.heightAnchor.constraint(equalToConstant: 1),
		])
	}

	static func sectionHeader(_ title: String) -> NSView
	{
		let header = NSView()
		let label = RemoteConnectionsLabel(
			title,
			role: TypographyTokens.Connections.section
		)
		label.translatesAutoresizingMaskIntoConstraints = false
		header.addSubview(label)
		NSLayoutConstraint.activate([
			header.heightAnchor.constraint(greaterThanOrEqualToConstant:
				LayoutTokens.Connections.sectionHeaderHeight),
			label.leadingAnchor.constraint(equalTo: header.leadingAnchor),
			label.topAnchor.constraint(
				equalTo: header.topAnchor,
				constant: 9.5
			),
			label.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor),
			label.bottomAnchor.constraint(lessThanOrEqualTo: header.bottomAnchor),
		])
		return header
	}

	static func row(
		title: String,
		detail: String?,
		control: NSView
	) -> SettingsControlRow
	{
		SettingsControlRow(
			title: title,
			detail: detail,
			control: control
		)
	}

	static func row(
		titleView: NSView,
		detailView: NSView,
		control: NSView
	) -> NSView
	{
		row(
			labels: [titleView, detailView],
			control: control
		)
	}

	private static func row(
		labels: [NSView],
		control: NSView
	) -> NSView
	{
		let row = NSView()
		SettingsRowLayout.install(
			labels: labels,
			control: control,
			in: row
		)
		return row
	}
}
