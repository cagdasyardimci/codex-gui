import AppKit

@MainActor
final class InspectorViewController: NSViewController
{
	enum Section: Int
	{
		case changes, projectContext
	}

	let changes = ChangesViewController()
	let projectContext = ProjectContextViewController()
	private let sectionControl = DesktopSegmentedControl(
		labels: ["Changes", "Context"],
		trackingMode: .selectOne,
		target: nil,
		action: nil
	)
	private let content = NSView()
	private let projectLabel = NSTextField(labelWithString: "Project")
	private var preferredBoxHeight: NSLayoutConstraint?
	private var hasReviewContent = false
	private(set) var section: Section = .changes

	override func loadView()
	{
		let container = DesktopSurface(DesktopTheme.canvas)
		let box = makeInspectorBox(in: container)

		configureHeaderControls()
		installInspectorContent(in: box)

		view = container
		show(section)
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

		sectionControl.selectedSegment = section.rawValue
		sectionControl.target = self
		sectionControl.action = #selector(selectSection)
		sectionControl.setAccessibilityLabel("Inspector section")
		sectionControl.segmentStyle = .rounded
		sectionControl.selectedSegmentBezelColor = DesktopTheme.selection
		sectionControl.controlSize = .small
		sectionControl.font = .systemFont(
			ofSize: 12,
			weight: .medium
		)
	}

	private func installInspectorContent(in box: NSView)
	{
		let divider = DesktopSurface(DesktopTheme.border)
		let stack = AppKitLayout.verticalStack(
			[projectLabel, sectionControl, divider, content],
			spacing: 12
		)
		stack.setCustomSpacing(
			16,
			after: sectionControl
		)
		AppKitLayout.pin(
			stack,
			to: box,
			inset: 16
		)
		projectLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		sectionControl.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
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
			hasReviewContent = !review.files.isEmpty || !review.validations.isEmpty
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
		let needsExpandedBox = section == .projectContext || hasReviewContent
		preferredBoxHeight?.constant = needsExpandedBox ? 440 : 300
	}

	func show(_ section: Section)
	{
		self.section = section
		guard isViewLoaded
		else
		{
			return
		}
		updateBoxHeight()
		sectionControl.selectedSegment = section.rawValue
		for child in children
		{
			child.view.removeFromSuperview()
			child.removeFromParent()
		}
		let controller: NSViewController = section == .changes ? changes : projectContext
		addChild(controller)
		AppKitLayout.pin(
			controller.view,
			to: content,
			inset: 0
		)
	}

	@objc private func selectSection()
	{
		show(Section(rawValue: sectionControl.selectedSegment) ?? .changes)
	}
}
