import AppKit

/// Complete toolbar-group variants own their surface, spacing and control-column geometry.
@MainActor
final class ViewerToolbarGroup: DesktopSurface
{
	enum Presentation
	{
		case actions, revisions, tools, tab, banner
	}

	init(
		_ content: NSView,
		presentation: Presentation
	)
	{
		let capsule = presentation == .actions || presentation == .revisions || presentation ==
			.tools
		let radius: CGFloat
		let horizontalInset: CGFloat
		let verticalInset: CGFloat
		switch presentation
		{
		case .actions:
			radius = 17; horizontalInset = 3; verticalInset = 3
		case .revisions:
			radius = 20; horizontalInset = 10; verticalInset = 4
		case .tools:
			radius = 20; horizontalInset = 6; verticalInset = 2.5
		case .tab:
			radius = 9; horizontalInset = 10; verticalInset = 2
		case .banner:
			radius = 20; horizontalInset = 10; verticalInset = 10
		}
		super.init(
			capsule ? AppKitColorTokens.canvas : AppKitColorTokens.elevated,
			cornerRadius: radius,
			bordered: capsule,
			borderColor: AppKitColorTokens.subtleEdge,
			shadows: capsule ? [ShadowTokens.fileViewerControl] : []
		)
		AppKitLayout.pin(
			content,
			to: self,
			insets: NSEdgeInsets(
				top: verticalInset,
				left: horizontalInset,
				bottom: verticalInset,
				right: horizontalInset
			)
		)
		if presentation == .revisions
		{
			heightAnchor.constraint(equalToConstant: 36).isActive = true
		}
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
