import Foundation

/// The standard disclosure direction is independent of each owner's visibility policy.
enum DesktopDisclosureIndicator: Equatable
{
	case hidden, collapsed, expanded

	init(
		expanded: Bool,
		visible: Bool = true
	)
	{
		self = visible ? (expanded ? .expanded : .collapsed) : .hidden
	}

	var icon: DesktopIcon?
	{
		switch self
		{
		case .hidden: nil
		case .collapsed: .chevronRight
		case .expanded: .chevronDown
		}
	}
}
