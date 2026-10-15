import Foundation

/// Shared radii, strokes and shape relationships, grouped by component role.
enum ShapeTokens
{
	enum CornerCurve: Sendable
	{
		case circular
		case superellipse(CGFloat)
	}

	enum Composer
	{
		static let cornerRadius: CGFloat = 22

		/// Uses the owning component's configured height.
		static func controlRadius(forControlHeight controlHeight: CGFloat) -> CGFloat
		{
			controlHeight / 2
		}
	}

	enum Inspector
	{
		static let summaryRadius: CGFloat = 20
		static let detailRadius: CGFloat = 16

		static let summaryEdgeWidth: CGFloat = 0.5
	}

	enum Toolbar
	{
		static let controlRadius: CGFloat = 9.375
		static let summaryToggleRadius: CGFloat = 12.5
	}

	enum SidebarSelection
	{
		static let cornerRadius: CGFloat = 12.5
		static let outlineWidth: CGFloat = 1

		static var outlineInset: CGFloat
		{
			outlineWidth / 2
		}

		static var outlineRadius: CGFloat
		{
			cornerRadius - outlineInset
		}
	}

	enum Transcript
	{
		static let codeCopyTooltipRadius: CGFloat = 12
		static let userRadius: CGFloat = 22

		static let resultRadius: CGFloat = 12
		static let replyControlRadius: CGFloat = 10
	}

	enum Markdown
	{
		static let codeRadius: CGFloat = 16

	}

	enum Popover
	{
		static let cornerRadius: CGFloat = 20
		static let edgeWidth: CGFloat = 0.5
	}

	enum ApprovalPopover
	{
		static let rowRadius: CGFloat = 12.5
		static let darkRowRadius: CGFloat = 15
	}

	enum ModelList
	{
		static let rowRadius: CGFloat = 15
	}

	enum EffortSlider
	{
		static let trackEdgeWidth: CGFloat = 0.5
		static var trackCornerRadius: CGFloat
		{
			LayoutTokens.EffortSlider.trackHeight / 2
		}
		static func knobRadius(diameter: CGFloat) -> CGFloat
		{
			diameter / 2
		}
	}

	enum TabControls
	{
		enum Role: Sendable
		{
			case close, standard
		}

		static let closeRadius: CGFloat = 10
		static let standardRadius: CGFloat = 12.5

		static let cornerCurve = CornerCurve.superellipse(1.5)
		static let selectedRadius: CGFloat = 10
		static let toolTileRadius: CGFloat = 10
		static let toolShortcutRadius: CGFloat = 10
		static let selectedEdgeWidth: CGFloat = 0.5

		static func radius(for role: Role) -> CGFloat
		{
			role == .close ? closeRadius : standardRadius
		}
	}

	enum NativeChrome
	{
		static let panelRadius: CGFloat = 12
	}

	enum TaskHover
	{
		static let cornerRadius: CGFloat = 15
	}
}
