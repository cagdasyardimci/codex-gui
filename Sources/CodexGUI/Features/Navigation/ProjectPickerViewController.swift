import AppKit

/// Search and project selection with a fixed creation action outside the scrolling list.
@MainActor
final class ProjectPickerViewController: NSViewController, NSSearchFieldDelegate,
	DesktopPopoverMaterialContent
{
	struct Project
	{
		let url: URL
		let name: String
	}
	var onSelect: ((URL) -> Void)?
	var onCreate: (() -> Void)?
	var onResize: (() -> Void)?
	let search = DesktopSearchField(presentation: .menuQuery)
	let scroll = DesktopMenuScrollView()
	let createRow = DesktopMenuRow(
		content: .init(
			title: "New project",
			icon: DesktopIcons.image(.plus)
		),
		textPresentation: .aligned
	)
	private let projects: [Project]
	private let results = DesktopFlippedStackView()
	private(set) var rows: [DesktopMenuRow] = []
	private var selectedIndex = 0
	private var scrollHeight: NSLayoutConstraint!

	init(projects: [Project])
	{
		self.projects = projects
		super.init(
			nibName: nil,
			bundle: nil
		)
	}
	required init?(coder: NSCoder)
	{
		nil
	}

	override func loadView()
	{
		search.configureSearch(
			placeholder: "Search projects",
			accessibilityLabel: "Search projects",
			delegate: self,
			sendsImmediately: true
		)
		results.orientation = .vertical
		results.alignment = .leading
		results.spacing = 0
		results.translatesAutoresizingMaskIntoConstraints = false
		scroll.documentView = results
		results.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
		scrollHeight = scroll.heightAnchor.constraint(equalToConstant: 0)
		scrollHeight.isActive = true
		createRow.onPreferredSizeChanged =
		{
			[weak self] in self?.resize()
		}
		createRow.onInvoke =
		{
			[weak self] in self?.onCreate?()
		}
		createRow.onHover =
		{
			[weak self] in self?.highlight(self?.rows.count ?? 0)
		}
		func separator() -> NSView
		{
			let container = NSView()
			let line = DesktopSurface(AppKitColorTokens.subtleEdge)
			AppKitLayout.pin(
				line,
				to: container,
				insets: NSEdgeInsets(
					top: 0,
					left: 8,
					bottom: 0,
					right: 8
				)
			)
			container.heightAnchor.constraint(equalToConstant: 1).isActive = true
			return container
		}
		let stack = AppKitLayout.verticalStack(
			[search, separator(), scroll, separator(), createRow],
			spacing: 4
		)
		let root = NSView(frame: NSRect(
			x: 0,
			y: 0,
			width: 304,
			height: 100
		))
		AppKitLayout.pin(
			stack,
			to: root,
			inset: 4
		)
		for row in stack
			.arrangedSubviews
		{
			row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		view = root
		reloadResults()
	}

	func controlTextDidChange(_ notification: Notification)
	{
		reloadResults()
	}

	func control(
		_ control: NSControl,
		textView: NSTextView,
		doCommandBy commandSelector: Selector
	) -> Bool
	{
		let key: UInt16
		switch commandSelector
		{
		case #selector(NSResponder.moveDown(_:)): key = 125
		case #selector(NSResponder.moveUp(_:)): key = 126
		case #selector(NSResponder.insertNewline(_:)): key = 36
		default: return false
		}
		return handleKey(key)
	}

	func handleKey(_ key: UInt16) -> Bool
	{
		DesktopMenuNavigation.handleKey(
			key,
			rows: rows + [createRow],
			currentIndex: (rows + [createRow])
				.firstIndex
				{
					$0 === view.window?.firstResponder
				} ?? selectedIndex,
			onHighlight: highlight,
			onChoose:
			{
				[self] in (rows + [createRow])[$0].accessibilityPerformPress()
			}
		)
	}

	private func highlight(_ index: Int)
	{
		selectedIndex = index
		for (offset, row) in (rows + [createRow])
			.enumerated()
		{
			row.menuHighlighted = offset == index
		}
		if rows.indices.contains(index)
		{
			rows[index].scrollToVisible(rows[index].bounds)
		}
	}

	private func reloadResults()
	{
		for row in results
			.arrangedSubviews
		{
			results.removeArrangedSubview(row); row.removeFromSuperview()
		}
		let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		let matches = projects
			.filter
			{
				query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.url
					.lastPathComponent.localizedCaseInsensitiveContains(query)
			}
		rows = matches.enumerated().map
		{
			index, project in
			let row = DesktopMenuRow(
				content: .init(
					title: project.name,
					icon: DesktopIcons.image(.folder),
					suffix: project.name == project.url.lastPathComponent ? "" : project.url
						.lastPathComponent,
					suffixStyle: .inlineMetadata
				),
				textPresentation: .aligned
			)
			row.onInvoke =
			{
				[weak self] in self?.onSelect?(project.url)
			}
			row.onHover =
			{
				[weak self] in self?.highlight(index)
			}
			row.onPreferredSizeChanged =
			{
				[weak self] in self?.resize()
			}
			results.addArrangedSubview(row)
			row.widthAnchor.constraint(equalTo: results.widthAnchor).isActive = true
			return row
		}
		highlight(0)
		scroll.contentView.scroll(to: .zero)
		resize()
	}

	private func resize()
	{
		scrollHeight.constant = min(
			196,
			rows.reduce(0)
			{
				$0 + $1.preferredSize.height
			}
		)
		preferredContentSize = NSSize(
			width: max(
				304,
				min(
					420,
					(rows.map
					{
						$0.preferredSize.width
					}.max() ?? 0) + 8
				)
			),
			height: search.intrinsicContentSize.height + scrollHeight.constant + createRow
				.preferredSize.height + 26
		)
		onResize?()
	}
}
