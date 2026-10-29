import AppKit

/// Navigation shared by menus whose rows expose native button actions.
@MainActor
enum DesktopMenuNavigation
{
	static func highlight(
		_ index: Int,
		rows: [DesktopMenuRow],
		in panel: NSPanel
	)
	{
		guard rows.indices.contains(index), rows[index].isEnabled
		else
		{
			return
		}
		for (offset, row) in rows.enumerated()
		{
			row.menuHighlighted = offset == index
		}
		rows[index].scrollToVisible(rows[index].bounds)
		panel.makeFirstResponder(rows[index])
	}

	static func handleKey(
		_ keyCode: UInt16,
		rows: [DesktopMenuRow],
		currentIndex: Int?,
		onHighlight: (Int) -> Void,
		onChoose: (Int) -> Bool
	) -> Bool
	{
		let enabled = rows.indices.filter
		{
			rows[$0].isEnabled
		}
		guard !enabled.isEmpty
		else
		{
			return false
		}
		let current = currentIndex.flatMap
		{
			enabled.firstIndex(of: $0)
		}
		switch keyCode
		{
		case 125, 126:
			let next = keyCode == 125 ? ((current ?? -1) + 1) % enabled.count
				: ((current ?? enabled.count) + enabled.count - 1) % enabled.count
			onHighlight(enabled[next])
			return true
		case 36, 76:
			guard let current
			else
			{
				return false
			}
			return onChoose(enabled[current])
		default: return false
		}
	}
}
