import AppKit

/// Native table context-menu lookup uses the pointer's row, without changing selection.
final class NavigationTasksTableView: NSTableView
{
	var onContextMenuForRow: ((Int) -> NSMenu?)?

	override func menu(for event: NSEvent) -> NSMenu?
	{
		let point = convert(
			event.locationInWindow,
			from: nil
		)
		guard bounds.contains(point)
		else
		{
			return nil
		}
		let clickedRow = row(at: point)
		guard clickedRow >= 0
		else
		{
			return nil
		}
		return onContextMenuForRow?(clickedRow)
	}
}
