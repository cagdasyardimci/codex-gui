import AppKit

/// Presents reported command evidence without treating a command exit as proof of test coverage.
@MainActor
final class ReviewValidationView: NSView
{
	private let commandButton = NSPopUpButton()
	private let statusLabel = NSTextField(wrappingLabelWithString: "")
	private let outputTextView = NSTextView()
	private var validations: [ReviewValidation] = []
	private struct ValidationIdentity: Equatable
	{
		let threadID: String
		let turnID: String
		let itemID: String
	}
	private var selectedIdentity: ValidationIdentity?

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		configure()
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func render(_ nextValidations: [ReviewValidation])
	{
		let previousIdentity = selectedIdentity
		validations = nextValidations
		commandButton.removeAllItems()
		if validations.isEmpty
		{
			commandButton.addItem(withTitle: "No command observed")
			commandButton.isEnabled = false
			selectedIdentity = nil
			statusLabel.stringValue = "Validation unobserved for this turn."
			outputTextView.string = "No command output was reported."
			outputTextView.sizeToFit()
			return
		}

		commandButton.isEnabled = true
		for validation in validations
		{
			let title =
				"Turn \(validation.turnID.prefix(8)) · \(validation.outcome.title) · "
					+ "\(validation.command)"
			commandButton.addItem(withTitle: title)
			commandButton.lastItem?.representedObject = validation.itemID
			commandButton.lastItem?.toolTip =
				"Thread \(validation.threadID), turn \(validation.turnID): \(validation.command)"
		}
		let selectedIndex =
			validations.firstIndex(where:
				{
					validation in
					ValidationIdentity(
						threadID: validation.threadID,
						turnID: validation.turnID,
						itemID: validation.itemID
					)
						== previousIdentity
				}) ?? 0
		commandButton.selectItem(at: selectedIndex)
		selectValidation(at: selectedIndex)
	}

	private func configure()
	{
		commandButton.target = self
		commandButton.action = #selector(commandChanged)
		commandButton.setAccessibilityLabel("Observed commands for reviewed code state")
		AppKitControlStyling.stylePopup(commandButton)
		AppKitLayout.compressHorizontally(commandButton)

		statusLabel.textColor = .secondaryLabelColor
		statusLabel.font = .systemFont(ofSize: 11)
		statusLabel.setAccessibilityLabel("Command outcome and code state")

		let outputScrollView = makeOutputScrollView()

		let stack = AppKitLayout.verticalStack(
			[commandButton, statusLabel, outputScrollView],
			spacing: 6
		)
		AppKitLayout.pin(
			stack,
			to: self,
			inset: 0
		)
		commandButton.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		outputScrollView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		outputScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 70).isActive = true
		outputScrollView.setContentHuggingPriority(
			.defaultLow,
			for: .vertical
		)
	}

	private func makeOutputScrollView() -> NSScrollView
	{
		outputTextView.isEditable = false
		outputTextView.isSelectable = true
		outputTextView.isHorizontallyResizable = false
		outputTextView.isVerticallyResizable = true
		outputTextView.autoresizingMask = [.width]
		outputTextView.minSize = .zero
		outputTextView.maxSize = NSSize(
			width: CGFloat.greatestFiniteMagnitude,
			height: CGFloat.greatestFiniteMagnitude
		)
		outputTextView.textContainer?.containerSize = NSSize(
			width: 200,
			height: CGFloat.greatestFiniteMagnitude
		)
		outputTextView.textContainer?.widthTracksTextView = true
		outputTextView.font = .monospacedSystemFont(
			ofSize: 11,
			weight: .regular
		)
		outputTextView.textContainerInset = NSSize(
			width: 8,
			height: 8
		)
		outputTextView.drawsBackground = false
		outputTextView.setAccessibilityLabel("Observed command output")

		let outputScrollView = NSScrollView()
		outputScrollView.documentView = outputTextView
		outputScrollView.hasVerticalScroller = true
		outputScrollView.autohidesScrollers = true
		outputScrollView.drawsBackground = false
		return outputScrollView
	}

	private func selectValidation(at index: Int)
	{
		guard validations.indices.contains(index)
		else
		{
			return
		}
		let validation = validations[index]
		selectedIdentity = ValidationIdentity(
			threadID: validation.threadID,
			turnID: validation.turnID,
			itemID: validation.itemID
		)

		statusLabel.stringValue = statusText(for: validation)
		outputTextView.string = evidenceText(for: validation)
		outputTextView.sizeToFit()
	}

	private func statusText(for validation: ReviewValidation) -> String
	{
		let timing =
			validation.currency == .outdated
				? "Outdated after later reported edits."
				: "Current repository state unverified."
		let exit = validation.exitCode.map
		{
			" Exit \($0)."
		} ?? " Exit code unavailable."
		return "\(validation.outcome.title).\(exit) \(timing)"
	}

	private func evidenceText(for validation: ReviewValidation) -> String
	{
		return
			"Command origin: thread \(validation.threadID), turn \(validation.turnID)\n"
				+ "Reported code state: \(validation.codeStateID)\n"
				+ "\(validation.scopeDescription)\n\n"
				+ (validation.output.flatMap
				{
					$0.isEmpty ? nil : $0
				}
				?? "No command output was reported.")
	}

	@objc private func commandChanged()
	{
		selectValidation(at: commandButton.indexOfSelectedItem)
	}
}

extension ReviewValidationOutcome
{
	fileprivate var title: String
	{
		switch self
		{
		case .succeeded: "Command succeeded"
		case .failed: "Command failed"
		case .unknown: "Command outcome unknown"
		case .unobserved: "Command result unobserved"
		}
	}
}
