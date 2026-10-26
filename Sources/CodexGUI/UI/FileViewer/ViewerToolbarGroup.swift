import AppKit

/// A shared group surface; its contents and responsive arrangement belong to the feature.
@MainActor
final class ViewerToolbarGroup: DesktopSurface
{
	enum Presentation
	{
		case flat, capsule
	}

	init(
		_ content: NSView,
		presentation: Presentation = .flat,
		radius: CGFloat = 20,
		horizontalInset: CGFloat = 10,
		verticalInset: CGFloat = 10
	)
	{
		super.init(
			presentation == .capsule ? AppKitColorTokens.canvas : AppKitColorTokens.elevated,
			cornerRadius: radius,
			bordered: presentation == .capsule,
			borderColor: AppKitColorTokens.subtleEdge,
			shadows: presentation == .capsule ? [ShadowTokens.fileViewerControl] : []
		)
		addSubview(content)
		content.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			content.leadingAnchor.constraint(
				equalTo: leadingAnchor,
				constant: horizontalInset
			),
			content.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -horizontalInset
			),
			content.topAnchor.constraint(
				equalTo: topAnchor,
				constant: verticalInset
			),
			content.bottomAnchor.constraint(
				equalTo: bottomAnchor,
				constant: -verticalInset
			)
		])
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
