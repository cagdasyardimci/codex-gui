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
		filterField.font = .systemFont(ofSize: 13)
		filterField.controlSize = .large
		filterField.isBezeled = false
		filterField.drawsBackground = false
		filterField.sendsSearchStringImmediately = true
		scrollView.documentView = tree
		scrollView.hasVerticalScroller = true
		scrollView.autohidesScrollers = true
		scrollView.drawsBackground = false

		let arranged = [headerView, filterField, statusView, scrollView].compactMap
		{
			$0
		}
		let stack = NSStackView(views: arranged)
		stack.orientation = .vertical
		stack.alignment = .width
		stack.spacing = 8
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)

		let insets = [
			stack.topAnchor.constraint(
				equalTo: topAnchor,
				constant: 8
			),
			stack.leadingAnchor.constraint(
				equalTo: leadingAnchor,
				constant: 8
			),
			stack.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -8
			),
			stack.bottomAnchor.constraint(
				equalTo: bottomAnchor,
				constant: -8
			)
		]
		// A hidden navigator has zero width during split-view transitions.
		for inset in insets
		{
			inset.priority = NSLayoutConstraint.Priority(999)
		}
		var constraints = insets + [
			filterField.heightAnchor.constraint(equalToConstant: 28),
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
