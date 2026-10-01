import AppKit

@MainActor
final class InspectorViewController: NSViewController
{
	let changes = ChangesViewController()
	private let content = NSView()
	private let projectLabel = NSTextField(labelWithString: "Project")
	private var preferredBoxHeight: NSLayoutConstraint?
	private var hasReviewContent = false

	override func loadView()
	{
		let container = DesktopSurface(DesktopTheme.canvas)
		let box = makeInspectorBox(in: container)

		configureHeaderControls()
		installInspectorContent(in: box)

		view = container
		addChild(changes)
		AppKitLayout.pin(
			changes.view,
			to: content,
			inset: 0
		)
	}

	private func makeInspectorBox(in container: NSView) -> NSView
	{
		let box = DesktopSurface(
			DesktopTheme.inspector,
			cornerRadius: 16
		)
		box.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(box)
		let preferredHeight = box.heightAnchor.constraint(equalToConstant: 300)
		// The box may yield space without raising the window's minimum content height.
		preferredHeight.priority = NSLayoutConstraint.Priority(1)
		preferredBoxHeight = preferredHeight
		NSLayoutConstraint.activate([
			box.leadingAnchor.constraint(
				equalTo: container.leadingAnchor,
				constant: 12
			),
			box.trailingAnchor.constraint(
				equalTo: container.trailingAnchor,
				constant: -12
			),
			box.topAnchor.constraint(
				equalTo: container.topAnchor,
				constant: 12
			),
			box.bottomAnchor.constraint(
				lessThanOrEqualTo: container.bottomAnchor,
				constant: -12
			),
			box.heightAnchor.constraint(lessThanOrEqualToConstant: 440),
			preferredHeight,
		])
		return box
	}

	private func configureHeaderControls()
	{
		projectLabel.font = .systemFont(
			ofSize: 13,
			weight: .regular
		)
		projectLabel.textColor = .secondaryLabelColor
		projectLabel.lineBreakMode = .byTruncatingMiddle
		projectLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		projectLabel.setAccessibilityLabel("Inspector project")
	}

	private func installInspectorContent(in box: NSView)
	{
		let divider = DesktopSurface(DesktopTheme.border)
		let stack = AppKitLayout.verticalStack(
			[projectLabel, divider, content],
			spacing: 12
		)
		AppKitLayout.pin(
			stack,
			to: box,
			inset: 16
		)
		projectLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		divider.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
		content.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		content.setContentHuggingPriority(
			.defaultLow,
			for: .vertical
		)
	}

	/// Updates the floating inspector's heading and height; child controllers render their own
	/// state.
	func render(_ snapshot: ConversationSnapshot)
	{
		render(ReviewPresentation(snapshot))
	}
	func render(_ snapshot: ReviewPresentation)
	{
		projectLabel.stringValue =
			snapshot.projectPath.map
				{
					URL(fileURLWithPath: $0).lastPathComponent
				} ?? "Project"
		projectLabel.toolTip = snapshot.projectPath
		if let review = snapshot.selectedReview
		{
			hasReviewContent = !review.files.isEmpty
		}
		else
		{
			hasReviewContent =
				snapshot.reviewTurns
					.isEmpty && (!snapshot.changedFiles.isEmpty || !snapshot.diff.isEmpty)
		}
		updateBoxHeight()
	}

	private func updateBoxHeight()
	{
		preferredBoxHeight?.constant = hasReviewContent ? 440 : 300
	}
}
