import AppKit

/// Bounded movement and command translation over the currently displayed results.
enum ViewerFileSearchSelection
{
	enum Direction: Equatable
	{
		case up, down, first, last
	}

	enum Command: Equatable
	{
		case navigate(Direction), accept, cancel
	}

	static func command(for selector: Selector) -> Command?
	{
		switch selector
		{
		case #selector(NSResponder.moveUp(_:)): .navigate(.up)
		case #selector(NSResponder.moveDown(_:)): .navigate(.down)
		case #selector(NSResponder.moveToBeginningOfDocument(_:)),
				#selector(NSResponder.moveToBeginningOfLine(_:)): .navigate(.first)
		case #selector(NSResponder.moveToEndOfDocument(_:)),
				#selector(NSResponder.moveToEndOfLine(_:)): .navigate(.last)
		case #selector(NSResponder.insertNewline(_:)): .accept
		case #selector(NSResponder.cancelOperation(_:)): .cancel
		default: nil
		}
	}

	static func command(forKeyCode keyCode: UInt16) -> Command?
	{
		switch keyCode
		{
		case 126: .navigate(.up)
		case 125: .navigate(.down)
		case 115: .navigate(.first)
		case 119: .navigate(.last)
		case 36, 76: .accept
		case 53: .cancel
		default: nil
		}
	}

	static func next(
		current: Int,
		count: Int,
		direction: Direction
	) -> Int?
	{
		guard count > 0
		else
		{
			return nil
		}
		if current < 0
		{
			return direction == .last ? count - 1 : 0
		}
		let selected = min(
			max(
				current,
				0
			),
			count - 1
		)
		switch direction
		{
		case .up: return max(
				0,
				selected - 1
			)
		case .down: return min(
				count - 1,
				selected + 1
			)
		case .first: return 0
		case .last: return count - 1
		}
	}
}
