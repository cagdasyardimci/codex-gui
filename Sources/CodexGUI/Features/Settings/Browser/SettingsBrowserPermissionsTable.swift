import AppKit

/// The site column stays fixed while the four permission columns scroll horizontally.
@MainActor
final class SettingsBrowserPermissionsTable: NSView
{
	private let scroll = NSScrollView()
	private let previous = RemoteConnectionsButton(
		title: "‹",
		presentation: .secondary
	)
	private let next = RemoteConnectionsButton(
		title: "›",
		presentation: .secondary
	)
	private var retainedActions: [SettingsBrowserActionButton] = []
	private let columnWidth: CGFloat = 160
	private let rowHeight: CGFloat = 66

	init(
		defaults: [String: Any],
		origins: [String: Any],
		enabled: Bool,
		onDefault: @escaping (
			String,
			Any
		) -> Void,
		onSite: @escaping (
			String,
			String,
			Any
		) -> Void,
		onEdit: @escaping (String) -> Void,
		onRemove: @escaping (String) -> Void
	)
	{
		super.init(frame: .zero)
		let sites = origins.keys.sorted()
		let card = RemoteConnectionsCard()
		let fixed = AppKitLayout.verticalStack(
			[],
			spacing: 0
		)
		fixed.addArrangedSubview(cell(
			"Site or pattern",
			header: true
		))
		fixed.addArrangedSubview(cell("Default permissions"))
		for site in sites
		{
			let label = NSTextField(labelWithString: site)
			label.font = .systemFont(
				ofSize: 13,
				weight: .medium
			)
			label.lineBreakMode = .byTruncatingMiddle
			label.toolTip = site
			let edit = SettingsBrowserActionButton(title: "Edit")
			{
				onEdit(site)
			}
			let remove = SettingsBrowserActionButton(title: "Remove")
			{
				onRemove(site)
			}
			for button in [edit, remove]
			{
				button.isEnabled = enabled
				retainedActions.append(button)
			}
			let buttons = NSStackView(views: [edit, remove])
			buttons.spacing = 4
			let stack = AppKitLayout.verticalStack(
				[label, buttons],
				spacing: 2
			)
			let row = NSView()
			AppKitLayout.pin(
				stack,
				to: row,
				inset: 8
			)
			row.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
			fixed.addArrangedSubview(row)
		}
		for row in fixed.arrangedSubviews
		{
			row.widthAnchor.constraint(equalTo: fixed.widthAnchor).isActive = true
		}
		let columns = NSStackView()
		columns.orientation = .horizontal
		columns.spacing = 0
		for field in SettingsBrowserPolicy.fields
		{
			let column = AppKitLayout.verticalStack(
				[],
				spacing: 0
			)
			column.addArrangedSubview(cell(
				field.title,
				header: true
			))
			let defaultPicker = picker(
				label: "Default \(field.title)",
				value: defaults[field.key] as? String,
				enabled: enabled
			)
			{
				value in onDefault(
					field.key,
					value
				)
			}
			column.addArrangedSubview(controlCell(defaultPicker))
			for site in sites
			{
				let policy = origins[site] as? [String: Any] ?? [:]
				let control = picker(
					label: "\(site) \(field.title)",
					value: policy[field.key] as? String,
					enabled: enabled
				)
				{
					value in onSite(
						site,
						field.key,
						value
					)
				}
				column.addArrangedSubview(controlCell(control))
			}
			column.widthAnchor.constraint(equalToConstant: columnWidth).isActive = true
			for row in column.arrangedSubviews
			{
				row.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
			}
			columns.addArrangedSubview(column)
		}
		scroll.drawsBackground = false
		scroll.contentView.drawsBackground = false
		scroll.hasHorizontalScroller = true
		scroll.autohidesScrollers = true
		scroll.documentView = columns
		columns.translatesAutoresizingMaskIntoConstraints = false
		scroll.contentView.postsBoundsChangedNotifications = true
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(updateArrows),
			name: NSView.boundsDidChangeNotification,
			object: scroll.contentView
		)
		for view in [fixed, scroll]
		{
			view.translatesAutoresizingMaskIntoConstraints = false
			card.addSubview(view)
		}
		NSLayoutConstraint.activate([
			fixed.leadingAnchor.constraint(
				equalTo: card.leadingAnchor,
				constant: 1
			),
			fixed.topAnchor.constraint(
				equalTo: card.topAnchor,
				constant: 1
			),
			fixed.bottomAnchor.constraint(
				equalTo: card.bottomAnchor,
				constant: -1
			),
			fixed.widthAnchor.constraint(equalToConstant: 190),
			scroll.leadingAnchor.constraint(equalTo: fixed.trailingAnchor),
			scroll.trailingAnchor.constraint(
				equalTo: card.trailingAnchor,
				constant: -1
			),
			scroll.topAnchor.constraint(
				equalTo: card.topAnchor,
				constant: 1
			),
			scroll.bottomAnchor.constraint(
				equalTo: card.bottomAnchor,
				constant: -1
			),
			columns.widthAnchor.constraint(equalToConstant: 4 * columnWidth),
			columns.heightAnchor.constraint(equalTo: fixed.heightAnchor),
		])
		previous.target = self
		previous.action = #selector(previousPage)
		previous.setAccessibilityLabel("Previous permission columns")
		next.target = self
		next.action = #selector(nextPage)
		next.setAccessibilityLabel("Next permission columns")
		let title = SettingsPageLayout.message("Website permissions")
		let spacer = NSView()
		let toolbar = NSStackView(views: [title, spacer, previous, next])
		toolbar.spacing = 8
		let stack = AppKitLayout.verticalStack(
			[toolbar, card],
			spacing: 8
		)
		AppKitLayout.pin(
			stack,
			to: self,
			inset: 0
		)
		for view in [toolbar, card]
		{
			view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		updateArrows()
	}

	var horizontalOffset: CGFloat
	{
		scroll.contentView.bounds.minX
	}

	func restoreHorizontalOffset(_ offset: CGFloat)
	{
		let maximum = max(
			0,
			4 * columnWidth - scroll.contentView.bounds.width
		)
		scroll.contentView.scroll(to: NSPoint(
			x: min(
				maximum,
				offset
			),
			y: 0
		))
		scroll.reflectScrolledClipView(scroll.contentView)
		updateArrows()
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func layout()
	{
		super.layout()
		updateArrows()
	}

	private func cell(
		_ title: String,
		header: Bool = false
	) -> NSView
	{
		let label = NSTextField(labelWithString: title)
		label.font = .systemFont(
			ofSize: header ? 12 : 13,
			weight: header ? .regular : .medium
		)
		label.textColor = header ? .secondaryLabelColor : .labelColor
		return controlCell(
			label,
			height: header ? 42 : rowHeight
		)
	}

	private func controlCell(
		_ control: NSView,
		height: CGFloat? = nil
	) -> NSView
	{
		let row = NSView()
		control.translatesAutoresizingMaskIntoConstraints = false
		row.addSubview(control)
		NSLayoutConstraint.activate([
			row.heightAnchor.constraint(equalToConstant: height ?? rowHeight),
			control.leadingAnchor.constraint(
				equalTo: row.leadingAnchor,
				constant: 12
			),
			control.trailingAnchor.constraint(
				lessThanOrEqualTo: row.trailingAnchor,
				constant: -8
			),
			control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
		])
		return row
	}

	private func picker(
		label: String,
		value: String?,
		enabled: Bool,
		onSelect: @escaping (Any) -> Void
	) -> SettingsChoicePicker
	{
		let picker = SettingsChoicePicker(
			choices: [
				.init(
					id: "default",
					title: "Use default"
				),
				.init(
					id: "allow",
					title: "Allow"
				),
				.init(
					id: "deny",
					title: "Block"
				),
			],
			selectedID: value ?? "default"
		)
		picker.isEnabled = enabled
		picker.setAccessibilityLabel(label)
		picker.onSelect =
		{
			onSelect($0 == "default" ? NSNull() : $0)
		}
		return picker
	}

	@objc private func previousPage()
	{
		moveColumns(direction: -1)
	}
	@objc private func nextPage()
	{
		moveColumns(direction: 1)
	}

	private func moveColumns(direction: CGFloat)
	{
		let maximum = max(
			0,
			4 * columnWidth - scroll.contentView.bounds.width
		)
		let x = min(
			maximum,
			max(
				0,
				scroll.contentView.bounds.minX + direction * 2 * columnWidth
			)
		)
		scroll.contentView.animator().setBoundsOrigin(NSPoint(
			x: x,
			y: 0
		))
		scroll.reflectScrolledClipView(scroll.contentView)
	}

	@objc private func updateArrows()
	{
		let maximum = max(
			0,
			4 * columnWidth - scroll.contentView.bounds.width
		)
		previous.isEnabled = scroll.contentView.bounds.minX > 0.5
		next.isEnabled = scroll.contentView.bounds.minX < maximum - 0.5
	}
}
