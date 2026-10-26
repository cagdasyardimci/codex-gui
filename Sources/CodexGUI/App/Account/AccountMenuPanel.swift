import AppKit

/// Account actions and selection inside the shared native popover shell.
@MainActor
final class AccountMenuPanel
{
	let content: StatusPopoverView
	private let host: DesktopPopoverHost
	private var selectedIndex: Int?
	var isShown: Bool
	{
		host.isShown
	}

	init(content: StatusPopoverView)
	{
		self.content = content
		host = DesktopPopoverHost(
			presentation: .account,
			content: content
		)
		content.onHoverRow =
		{
			[weak self] index in self?.focus(index)
		}
		content.setAccessibilityRole(.menu)
		content.setAccessibilityLabel("Account menu")
		host.onKeyDown =
		{
			[weak self] event in self?.handleKey(event.keyCode) ?? false
		}
		host.typeaheadRows =
		{
			[weak self] in self?.content.menuButtons ?? []
		}
		host.onTypeaheadSelection =
		{
			[weak self] row in
			guard let self, let index = content.menuButtons.firstIndex(where:
				{
					$0 === row
				})
			else
			{
				return
			}
			focus(index)
		}

	}

	func show(from anchor: NSView)
	{
		guard anchor.window != nil
		else
		{
			return
		}
		close()
		selectedIndex = nil
		content.highlightMenuItem(nil)
		host.show(from: anchor)
	}

	func close()
	{
		host.close()
	}

	func shouldForward(_ event: NSEvent) -> Bool
	{
		host.shouldForward(event)
	}

	@discardableResult func handleKey(_ keyCode: UInt16) -> Bool
	{
		switch keyCode
		{
		case 53, 48: close()
		case 125, 126:
			let buttons = content.menuButtons
			let offset = keyCode == 125 ? 1 : -1
			var next = selectedIndex ?? (offset == 1 ? -1 : 0)
			for _ in buttons.indices
			{
				next = (next + offset + buttons.count) % buttons.count
				if buttons[next].isEnabled, buttons[next].action != nil
				{
					focus(next)
					break
				}
			}
		case 36, 76, 49:
			if let selectedIndex
			{
				let button = content.menuButtons[selectedIndex]
				if button.isEnabled, let action = button.action
				{
					button.sendAction(
						action,
						to: button.target
					)
				}
			}
		default: return false
		}
		return true
	}

	private func focus(_ index: Int)
	{
		guard content.menuButtons[index].isEnabled
		else
		{
			return
		}
		selectedIndex = content.menuButtons[index].action == nil ? nil : index
		content.highlightMenuItem(index)
		if selectedIndex != nil
		{
			host.panel.makeFirstResponder(content.menuButtons[index])
		}
	}

}
