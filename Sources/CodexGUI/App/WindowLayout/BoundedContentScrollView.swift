import AppKit

/// Keeps variable request details scrollable instead of increasing the window's minimum size.
@MainActor
final class BoundedContentScrollView: NSScrollView
{
	private static let minimumContentHeight: CGFloat = 36
	private static let maximumContentHeight: CGFloat = 140

	private let contentStack: NSStackView
	private var preferredHeight: NSLayoutConstraint!

	init(views: [NSView])
	{
		contentStack = AppKitLayout.verticalStack(
			views,
			spacing: 6
		)
		super.init(frame: .zero)

		hasVerticalScroller = true
		autohidesScrollers = true

		let document = DesktopFlippedView()
		AppKitLayout.pin(
			contentStack,
			to: document,
			inset: 0
		)
		document.translatesAutoresizingMaskIntoConstraints = false
		documentView = document
		document.widthAnchor.constraint(equalTo: contentView.widthAnchor).isActive = true
		for view in views
		{
			view.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
		}

		heightAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumContentHeight)
			.isActive = true
		heightAnchor.constraint(lessThanOrEqualToConstant: Self.maximumContentHeight)
			.isActive = true
		preferredHeight = heightAnchor.constraint(equalToConstant: Self.minimumContentHeight)
		// Let window fitting use the scrollable minimum; spare space can still reveal more details.
		preferredHeight.priority = NSLayoutConstraint.Priority(
			rawValue: NSLayoutConstraint.Priority.fittingSizeCompression.rawValue - 1
		)
		preferredHeight.isActive = true
		isHidden = true
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func updateContentHeight()
	{
		isHidden = contentStack.arrangedSubviews.allSatisfy(\.isHidden)
		guard !isHidden
		else
		{
			return
		}
		documentView?.layoutSubtreeIfNeeded()
		let minimumFittingHeight = max(
			Self.minimumContentHeight,
			contentStack.fittingSize.height
		)
		preferredHeight.constant = min(
			Self.maximumContentHeight,
			minimumFittingHeight
		)
	}
}
