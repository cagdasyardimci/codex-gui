import AppKit

/// A shared group surface; its contents and responsive arrangement belong to the feature.
@MainActor
final class ViewerToolbarGroup: DesktopSurface
{
	init(
		_ content: NSView,
		radius: CGFloat = 20,
		horizontalInset: CGFloat = 10,
		verticalInset: CGFloat = 10
	)
	{
		super.init(
			AppKitColorTokens.elevated,
			cornerRadius: radius
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
