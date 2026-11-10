import AppKit

/// Shared action rows, keyboard navigation and dismissal for an app-owned menu surface.
@MainActor
final class DesktopActionMenu: NSObject
{
	let rows: [DesktopMenuRow]
	private(set) var host: DesktopPopoverHost!
	private let items: [NSMenuItem]
	private let content: DesktopActionMenuContent
	private let minimumWidth: CGFloat
	private let backingScale: CGFloat
	private let placement: DesktopPopoverHost.ComposerPlacement
	var onClose: (() -> Void)?

	init(
		menu: NSMenu,
		backingScale: CGFloat = 1,
		minimumWidth: CGFloat = 0,
		alignment: DesktopPopoverHost.ComposerPlacement.Alignment = .trailing,
		showsCheckmarks: Bool = false,
		accessibilityLabel: String = "Queued message actions"
	)
	{
		self.minimumWidth = minimumWidth
		placement = DesktopPopoverHost.ComposerPlacement(
			alignment: alignment,
			anchorSpacing: 5,
			opensBelowAnchor: true
		)
		self.backingScale = backingScale
		items = menu.items.filter
		{
			!$0.isHidden && !$0.isSeparatorItem
		}
		rows = items.map
		{
			item in
			let row = DesktopMenuRow(
				content: .init(
					title: item.title,
					icon: item.image,
					indicator: showsCheckmarks ? .checkmark : .none,
					checked: item.state == .on
				),
				textPresentation: .aligned
			)
			row.isEnabled = item.isEnabled
			return row
		}
		content = DesktopActionMenuContent(
			rows: rows,
			items: menu.items.filter
			{
				!$0.isHidden
			},
			accessibilityLabel: accessibilityLabel
		)
		super.init()
		refreshSize()
		content.loadViewIfNeeded()
		host = DesktopPopoverHost(
			presentation: .composer(placement),
			content: content.view,
			controller: content,
			shadowOutset: 24
		)
		host.onPresentationChange =
		{
			[weak self] shown in
			if !shown
			{
				self?.rows.forEach
				{
					$0.clearHover(); $0.menuHighlighted = false
				}; self?.onClose?()
			}
		}
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
		host.onKeyDown =
		{
			[weak self] event in self?.handleKey(event) ?? false
		}
		for (index, row) in rows.enumerated()
		{
			row.onPreferredSizeChanged =
			{
				[weak self] in self?.refreshSize()
			}
			row.onHover =
			{
				[weak self] in self?.highlight(index)
			}
			row.onInvoke =
			{
				[weak self] in
				guard let self
				else
				{
					return
				}
				let item = self.items[index]
				self.host.close()
				if let action = item
					.action
				{
					NSApp.sendAction(
						action,
						to: item.target,
						from: item
					)
				}
			}
			row.nextKeyView = rows[(index + 1) % rows.count]
		}
	}

	private func refreshSize()
	{
		let rowSizes = rows.map(\.preferredSize)
		content.preferredContentSize = NSSize(
			width: ceil(max(
				minimumWidth,
				(rowSizes.map(\.width).max() ?? 0) + 2 * DesktopActionMenuContent.inset
			) * backingScale) / backingScale,
			height: 2 * DesktopActionMenuContent.inset + rowSizes
				.reduce(0)
				{
					$0 + $1.height
				} + CGFloat(content.separatorCount) *
				DesktopActionMenuContent.separatorHeight
		)
		host?.update(.composer(placement))
	}

	func show(from anchor: NSView)
	{
		host.show(from: anchor)
	}
	func close()
	{
		host.close()
	}

	private func highlight(_ index: Int)
	{
		for (offset, row) in rows.enumerated() where offset != index
		{
			row.clearHover()
		}
		DesktopMenuNavigation.highlight(
			index,
			rows: rows,
			in: host.panel
		)
	}

	private func handleKey(_ event: NSEvent) -> Bool
	{
		DesktopMenuNavigation.handleKey(
			event.keyCode,
			rows: rows,
			currentIndex: rows.firstIndex
			{
				$0 === host.panel.firstResponder
			},
			onHighlight: highlight,
			onChoose:
			{
				rows[$0].accessibilityPerformPress()
			}
		)
	}
}

@MainActor
private final class DesktopActionMenuContent: NSViewController, DesktopPopoverMaterialContent
{
	static let inset: CGFloat = 4
	static let separatorHeight: CGFloat = 9
	var separatorCount: Int
	{
		items.filter(\.isSeparatorItem).count
	}

	private let rows: [DesktopMenuRow]
	private let items: [NSMenuItem]
	private let accessibilityLabel: String
	init(
		rows: [DesktopMenuRow],
		items: [NSMenuItem],
		accessibilityLabel: String
	)
	{
		self.rows = rows
		self.items = items
		self.accessibilityLabel = accessibilityLabel
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
		let root = NSView()
		root.setAccessibilityElement(true)
		root.setAccessibilityRole(.menu)
		root.setAccessibilityLabel(accessibilityLabel)
		var rowIndex = 0
		let content: [NSView] = items.map
		{
			item in
			if item.isSeparatorItem
			{
				let separator = NSView()
				let line = DesktopSurface(AppKitColorTokens.subtleEdge)
				AppKitLayout.pin(
					line,
					to: separator,
					insets: NSEdgeInsets(
						top: 4,
						left: 8,
						bottom: 4,
						right: 8
					)
				)
				separator.heightAnchor.constraint(equalToConstant: Self.separatorHeight)
					.isActive = true
				return separator
			}
			defer
			{
				rowIndex += 1
			}
			return rows[rowIndex]
		}
		let stack = AppKitLayout.verticalStack(
			content,
			spacing: 0
		)
		AppKitLayout.pin(
			stack,
			to: root,
			inset: Self.inset
		)
		for row in content
		{
			row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		view = root
	}
}
