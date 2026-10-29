import AppKit

@MainActor
final class ComposerQueueMenu: NSObject
{
	let rows: [DesktopMenuRow]
	private(set) var host: DesktopPopoverHost!
	private let menu: NSMenu
	var onClose: (() -> Void)?

	init(
		menu: NSMenu,
		backingScale: CGFloat = 1
	)
	{
		self.menu = menu
		rows = menu.items.map
		{
			item in
			let row = DesktopMenuRow(
				content: .init(
					title: item.title,
					icon: item.image
				),
				textPresentation: .aligned
			)
			row.isEnabled = item.isEnabled
			return row
		}
		super.init()
		let content = ComposerQueueMenuContent(rows: rows)
		let rowSizes = rows.map(\.preferredSize)
		content.preferredContentSize = NSSize(
			width: ceil(((rowSizes.map(\.width).max() ?? 0) + 2 * ComposerQueueMenuContent.inset) *
				backingScale) / backingScale,
			height: 2 * ComposerQueueMenuContent.inset + rowSizes.reduce(0)
			{
				$0 + $1.height
			}
		)
		content.loadViewIfNeeded()
		host = DesktopPopoverHost(
			presentation: .composer(.init(
				alignment: .trailing,
				anchorSpacing: 5,
				opensBelowAnchor: true
			)),
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
				let item = self.menu.items[index]
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
private final class ComposerQueueMenuContent: NSViewController, DesktopPopoverMaterialContent
{
	static let inset: CGFloat = 4

	private let rows: [DesktopMenuRow]
	init(rows: [DesktopMenuRow])
	{
		self.rows = rows
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
		root.setAccessibilityLabel("Queued message actions")
		let stack = AppKitLayout.verticalStack(
			rows,
			spacing: 0
		)
		AppKitLayout.pin(
			stack,
			to: root,
			inset: Self.inset
		)
		for row in rows
		{
			row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		view = root
	}
}
