import AppKit

/// Shared filter and scroll surface around a file tree. Feature headers and status stay optional.
@MainActor
final class ViewerFileNavigatorView: NSView
{
	let scrollView = NSScrollView()

	init(
		filterField: ViewerSearchField,
		tree: ViewerFileTreeView,
		headerView: NSView? = nil,
		statusView: NSView? = nil
	)
	{
		super.init(frame: .zero)
		filterField.placeholderString = "Filter files…"
		filterField.presentation = .viewer
		filterField.sendsSearchStringImmediately = true
		scrollView.documentView = tree
		scrollView.hasVerticalScroller = true
		scrollView.autohidesScrollers = true
		scrollView.drawsBackground = false

		let arranged = [headerView, filterField, statusView, scrollView].compactMap
		{
			$0
		}
		let stack = AppKitLayout.verticalStack(
			arranged,
			spacing: 8,
			alignment: .width
		)
		// A hidden navigator has zero width during split-view transitions.
		AppKitLayout.pin(
			stack,
			to: self,
			inset: 8,
			priority: NSLayoutConstraint.Priority(999)
		)
		var constraints = [
			scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 100)
		]
		for view in arranged
		{
			constraints.append(view.widthAnchor.constraint(equalTo: stack.widthAnchor))
		}
		NSLayoutConstraint.activate(constraints)
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
