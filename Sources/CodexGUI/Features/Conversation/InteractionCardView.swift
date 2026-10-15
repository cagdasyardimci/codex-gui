import AppKit

@MainActor
final class InteractionCardView: NSView
{
	private let interaction: PendingInteraction
	private let onRespond: (InteractionResponse) -> Void
	private var answerControls:
		[(question: InteractionQuestion, menu: NSPopUpButton, customAnswerField: NSTextField)] = []
	private var approvalDecisions: [ApprovalDecision] = []
	private let messageLabel = NSTextField(labelWithString: "")

	init(
		interaction: PendingInteraction,
		onRespond: @escaping (InteractionResponse) -> Void
	)
	{
		self.interaction = interaction
		self.onRespond = onRespond
		super.init(frame: .zero)
		buildView()
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	private func buildView()
	{
		let title = NSTextField(labelWithString: titleText)
		title.font = .systemFont(
			ofSize: 13,
			weight: .semibold
		)
		title.setAccessibilityLabel(titleText)

		let details = NSTextField(wrappingLabelWithString: detailText)
		details.font = .systemFont(ofSize: 12)
		details.isSelectable = true
		details.setAccessibilityLabel(detailText)

		messageLabel.textColor = .systemRed
		messageLabel.isHidden = true

		let content = AppKitLayout.verticalStack(
			[title, details],
			spacing: 8
		)
		addResponseControls(to: content)
		content.addArrangedSubview(messageLabel)
		styleControls(in: content)

		installCardSurface(containing: content)
		setAccessibilityLabel(titleText)
	}

	private func addResponseControls(to content: NSStackView)
	{
		switch interaction.kind
		{
		case .question:
			addQuestionControls(to: content)
			let answerButton = NSButton(
				title: "Submit Answer",
				target: self,
				action: #selector(submitAnswers)
			)
			answerButton.setAccessibilityLabel("Submit answers to Codex")
			content.addArrangedSubview(answerButton)
		case .commandApproval, .fileChangeApproval:
			addApprovalControls(to: content)
		case .permissionApproval:
			addPermissionControls(to: content)
		case .unsupported:
			content.addArrangedSubview(
				NSTextField(wrappingLabelWithString: "Codex GUI cannot answer this request.")
			)
		}
	}

	private func installCardSurface(containing content: NSStackView)
	{
		let box = NSBox()
		box.boxType = .custom
		box.borderColor = AppKitColorTokens.border
		box.fillColor = AppKitColorTokens.elevated
		box.cornerRadius = 12
		box.contentView = content
		addSubview(box)
		box.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			box.leadingAnchor.constraint(equalTo: leadingAnchor),
			box.trailingAnchor.constraint(equalTo: trailingAnchor),
			box.topAnchor.constraint(equalTo: topAnchor),
			box.bottomAnchor.constraint(equalTo: bottomAnchor),
			content.leadingAnchor.constraint(
				equalTo: box.leadingAnchor,
				constant: 12
			),
			content.trailingAnchor.constraint(
				equalTo: box.trailingAnchor,
				constant: -12
			),
			content.topAnchor.constraint(
				equalTo: box.topAnchor,
				constant: 12
			),
			content.bottomAnchor.constraint(
				equalTo: box.bottomAnchor,
				constant: -12
			),
		])
	}

	private func styleControls(in view: NSView)
	{
		if let popup = view as? NSPopUpButton
		{
			AppKitControlStyling.stylePopup(popup)
		}
		else if let button = view as? NSButton
		{
			AppKitControlStyling.styleButton(button)
		}
		for child in view.subviews
		{
			styleControls(in: child)
		}
	}

	private var titleText: String
	{
		switch interaction.kind
		{
		case .commandApproval: "Command approval requested"
		case .fileChangeApproval: "File change approval requested"
		case .permissionApproval: "Permission requested"
		case .question: "Codex has a question"
		case .unsupported(let method): "Unsupported request: \(method)"
		}
	}

	private var detailText: String
	{
		var lines: [String] = []
		if let command = interaction.command
		{
			lines.append("Command: \(command)")
		}
		if let cwd = interaction.cwd
		{
			lines.append("Working directory: \(cwd)")
		}
		if let root = interaction.grantRoot
		{
			lines.append("Path: \(root)")
		}
		if let host = interaction.networkHost
		{
			let destination = [interaction.networkProtocol, host].compactMap
			{
				$0
			}.joined(separator: "://")
			lines.append("Network destination: \(destination)")
		}
		if let reason = interaction.reason
		{
			lines.append("Reason: \(reason)")
		}
		if let permissions = interaction.requestedPermissions
		{
			lines.append("Requested access:\n\(Self.describe(permissions))")
		}
		if let permissions = interaction.additionalPermissions
		{
			lines.append("Additional command access:\n\(Self.describe(permissions))")
		}
		for decision in interaction.availableDecisions ?? []
		{
			switch decision
			{
			case .acceptWithExecpolicyAmendment(let commands):
				lines.append("Proposed command rule: \(commands.joined(separator: " "))")
			case .applyNetworkPolicyAmendment(
				let host,
				let action
			):
				lines.append("Proposed network rule: \(action) \(host)")
			default: break
			}
		}
		return lines.isEmpty
			? "Codex needs your input before it can continue." : lines.joined(separator: "\n")
	}

	private static func describe(_ permissions: [String: Any]) -> String
	{
		guard
			let data = try? JSONSerialization.data(
				withJSONObject: permissions,
				options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
			),
			let text = String(
				data: data,
				encoding: .utf8
			)
		else
		{
			return "Access details are unavailable."
		}
		return text
	}

	private func addApprovalControls(to content: NSStackView)
	{
		approvalDecisions =
			interaction.availableDecisions ?? [
				.accept,
				.acceptForSession,
				.decline,
				.cancel,
			]
		if approvalDecisions.isEmpty
		{
			content.addArrangedSubview(
				NSTextField(
					wrappingLabelWithString:
					"Codex offered no supported decisions. Stop the task to cancel it."
				)
			)
			return
		}
		let buttons = approvalDecisions.enumerated().map
		{
			index, decision in
			let button = NSButton(
				title: title(for: decision),
				target: self,
				action: #selector(chooseApproval(_:))
			)
			button.tag = index
			button.setAccessibilityLabel(button.title)
			return button
		}
		content.addArrangedSubview(AppKitLayout.horizontalStack(buttons))
	}

	private func title(for decision: ApprovalDecision) -> String
	{
		switch decision
		{
		case .accept: "Approve Once"
		case .acceptForSession: "Approve for Session"
		case .decline: "Deny"
		case .cancel: "Deny and Stop"
		case .acceptWithExecpolicyAmendment: "Approve and Save Command Rule"
		case .applyNetworkPolicyAmendment(
			_,
			let action
		):
			action == "allow" ? "Allow Network Rule" : "Deny Network Rule"
		}
	}

	private func addPermissionControls(to content: NSStackView)
	{
		var buttons: [NSView] = []
		if let requested = interaction.requestedPermissions, !requested.isEmpty
		{
			let once = NSButton(
				title: "Allow for Turn",
				target: self,
				action: #selector(allowOnce)
			)
			let session = NSButton(
				title: "Allow for Session",
				target: self,
				action: #selector(allowSession)
			)
			once.setAccessibilityLabel("Allow requested access for this turn")
			session.setAccessibilityLabel("Allow requested access for this session")
			buttons.append(contentsOf: [once, session])
		}
		let deny = NSButton(
			title: "Deny",
			target: self,
			action: #selector(denyPermission)
		)
		deny.setAccessibilityLabel("Deny requested access")
		buttons.append(deny)
		content.addArrangedSubview(AppKitLayout.horizontalStack(buttons))
	}

	private func addQuestionControls(to content: NSStackView)
	{
		for question in interaction.questions
		{
			let questionLabel = NSTextField(wrappingLabelWithString: question.question)
			questionLabel.font = .systemFont(ofSize: 13)
			content.addArrangedSubview(questionLabel)

			let menu = NSPopUpButton()
			menu.addItem(withTitle: "Choose an answer…")
			menu.item(at: 0)?.isEnabled = false
			for option in question.options
			{
				menu.addItem(withTitle: option.label)
				menu.lastItem?.toolTip = option.description
			}
			if question.allowsOther || question.options.isEmpty
			{
				menu.addItem(withTitle: "Other…")
			}
			menu.setAccessibilityLabel("Answer for \(question.header)")
			content.addArrangedSubview(menu)

			let customAnswerField = question.isSecret ? NSSecureTextField() : NSTextField()
			customAnswerField.placeholderString = "Enter an answer"
			customAnswerField.setAccessibilityLabel("Custom answer for \(question.header)")
			content.addArrangedSubview(customAnswerField)
			customAnswerField.widthAnchor.constraint(greaterThanOrEqualToConstant: 240)
				.isActive = true
			answerControls.append((question, menu, customAnswerField))
		}
	}

	@objc private func submitAnswers()
	{
		var answers: [String: [String]] = [:]
		for (question, menu, customAnswerField) in answerControls
		{
			let customAnswer = customAnswerField.stringValue
				.trimmingCharacters(in: .whitespacesAndNewlines)
			let selectedAnswer = menu.selectedItem?.title ?? ""
			let answer = !customAnswer.isEmpty ? customAnswer : selectedAnswer
			guard !answer.isEmpty, answer != "Choose an answer…", answer != "Other…"
			else
			{
				messageLabel.stringValue = "Answer every question before submitting."
				messageLabel.isHidden = false
				return
			}
			answers[question.id] = [answer]
		}
		onRespond(.answers(answers))
	}

	@objc private func chooseApproval(_ sender: NSButton)
	{
		guard approvalDecisions.indices.contains(sender.tag)
		else
		{
			return
		}
		onRespond(.approval(approvalDecisions[sender.tag]))
	}

	@objc private func denyPermission()
	{
		onRespond(.permissions(
			granted: [:],
			scope: .turn
		))
	}

	@objc private func allowOnce()
	{
		onRespond(.permissions(
			granted: interaction.requestedPermissions ?? [:],
			scope: .turn
		))
	}

	@objc private func allowSession()
	{
		onRespond(.permissions(
			granted: interaction.requestedPermissions ?? [:],
			scope: .session
		))
	}
}
