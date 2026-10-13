import AppKit

enum WindowPaneLayout
{
	private static let metrics: LayoutTokens.Window =
	{
		let metrics = LayoutTokens.window
		let summaryWidth = LayoutTokens.Inspector.summaryPaneWidth
		precondition(
			metrics.isValid(summaryPreferredWidth: summaryWidth),
			"Invalid window metrics for the active pane modes"
		)
		return metrics
	}()
	static let version = 2
	static var navigationWidth: CGFloat
	{
		metrics.navigationWidth
	}
	static var navigationMinimumWidth: CGFloat
	{
		metrics.navigationMinimumWidth
	}
	static var navigationMaximumWidth: CGFloat
	{
		metrics.navigationMaximumWidth
	}
	static var reviewWidth: CGFloat
	{
		metrics.reviewWidth
	}
	static var reviewMinimumWidth: CGFloat
	{
		metrics.reviewMinimumWidth
	}
	static var toolsMinimumWidth: CGFloat
	{
		metrics.toolsMinimumWidth
	}
	static var reviewMaximumWidth: CGFloat
	{
		metrics.reviewMaximumWidth
	}
	static var conversationMinimumWidth: CGFloat
	{
		metrics.conversationMinimumWidth
	}
	static var toolsConversationMinimumWidth: CGFloat
	{
		metrics.toolsConversationMinimumWidth
	}
	static var conversationComfortableWidth: CGFloat
	{
		metrics.conversationComfortableWidth
	}
	// Divider dragging has priority 490; side panes must yield to that interaction.
	static let sideHoldingPriority = NSLayoutConstraint.Priority(400)

	static func restoredNavigationWidth(_ width: CGFloat) -> CGFloat
	{
		restoredWidth(
			width,
			minimum: navigationMinimumWidth,
			maximum: navigationMaximumWidth,
			fallback: navigationWidth
		)
	}

	static func restoredReviewWidth(_ width: CGFloat) -> CGFloat
	{
		restoredWidth(
			width,
			minimum: reviewMinimumWidth,
			maximum: reviewMaximumWidth,
			fallback: reviewWidth
		)
	}

	private static func restoredWidth(
		_ width: CGFloat,
		minimum: CGFloat,
		maximum: CGFloat,
		fallback: CGFloat
	) -> CGFloat
	{
		guard width.isFinite, (minimum ... maximum).contains(width)
		else
		{
			return fallback
		}
		return width
	}
}

enum WindowReviewVisibility: String, Codable
{
	case automatic
	case expanded
	case collapsed
}

struct WindowLayout: Codable, Equatable
{
	var frame: CGRect
	var navigationWidth: CGFloat
	var reviewWidth: CGFloat
	var reviewCollapsed: Bool
	// Older saved layouts did not retain the sidebar's collapse state.
	var navigationCollapsed: Bool? = nil
	var paneGeometryVersion: Int? = nil
	var reviewVisibility: WindowReviewVisibility? = nil

	var restoredPaneWidths: WindowLayout
	{
		var layout = self
		if paneGeometryVersion == WindowPaneLayout.version
		{
			layout.navigationWidth = WindowPaneLayout.restoredNavigationWidth(navigationWidth)
			layout.reviewWidth = WindowPaneLayout.restoredReviewWidth(reviewWidth)
		}
		else
		{
			// Replace proportional legacy geometry once, without changing the window or collapse
			// states.
			layout.navigationWidth = WindowPaneLayout.navigationWidth
			layout.reviewWidth = WindowPaneLayout.reviewWidth
		}

		layout.paneGeometryVersion = WindowPaneLayout.version
		if layout.reviewVisibility == nil
		{
			layout.reviewVisibility = reviewCollapsed ? .collapsed : .automatic
		}
		return layout
	}

	func visibleFrame(
		on screens: [CGRect],
		minimumSize: CGSize
	) -> CGRect
	{
		guard
			let screen = screens.max(by:
				{
					frame.intersection($0).area < frame.intersection($1).area
				})
		else
		{
			return frame
		}
		// Fit the saved dimensions first, then keep the entire frame on the chosen screen.
		let requestedWidth = max(
			minimumSize.width,
			frame.width
		)
		let requestedHeight = max(
			minimumSize.height,
			frame.height
		)
		let visibleSize = CGSize(
			width: min(
				screen.width,
				requestedWidth
			),
			height: min(
				screen.height,
				requestedHeight
			)
		)

		let leadingX = max(
			frame.minX,
			screen.minX
		)
		let bottomY = max(
			frame.minY,
			screen.minY
		)
		return CGRect(
			x: min(
				leadingX,
				screen.maxX - visibleSize.width
			),
			y: min(
				bottomY,
				screen.maxY - visibleSize.height
			),
			width: visibleSize.width,
			height: visibleSize.height
		)
	}
}

@MainActor
final class WindowLayoutStore
{
	private let defaults: UserDefaults
	private let key = "CodexGUI.windowLayout"

	init(defaults: UserDefaults = ApplicationPreferences.defaultStore)
	{
		self.defaults = defaults
	}

	var layout: WindowLayout?
	{
		get
		{
			guard let data = defaults.data(forKey: key)
			else
			{
				return nil
			}
			guard let storedLayout = try? JSONDecoder().decode(
				WindowLayout.self,
				from: data
			)
			else
			{
				return nil
			}
			let restoredLayout = storedLayout.restoredPaneWidths
			if restoredLayout != storedLayout
			{
				defaults.set(
					try? JSONEncoder().encode(restoredLayout),
					forKey: key
				)
			}
			return restoredLayout
		}
		set
		{
			defaults.set(
				try? JSONEncoder().encode(newValue?.restoredPaneWidths),
				forKey: key
			)
		}
	}
}

extension CGRect
{
	fileprivate var area: CGFloat
	{
		isNull ? 0 : width * height
	}
}
