import AppKit

/// Presents a sequence of questions belonging to a single server request.
@MainActor
final class QuestionCardView: NSView, NSTextFieldDelegate
{
	private let interaction: PendingInteraction
	private let onRespond: (InteractionResponse) -> Void
	private let onClose: () -> Void
	private let content = AppKitLayout.verticalStack(
		[],
		spacing: 12
	)
	private var index = 0
	private var answers: [String: String] = [:]
	private var field: NSTextField?
	private var primaryButton: DesktopStyledButton?
	private var hidesEmptyPrimary = false
	private var inputHeight: NSLayoutConstraint?
	private let dictation = QuestionDictationController()
	private var dictationButton: DesktopStyledButton?
	private var recordingView: QuestionRecordingView?
	private var answerViews: [NSView] = []
	private var footerSpacer: NSView?
	private var dictationDraft = ""
	private var isFinalizingDictation = false
	private var submitsDictation = false
	var onContentSizeChanged: (() -> Void)?

	init(
		interaction: PendingInteraction,
		onRespond: @escaping (InteractionResponse) -> Void,
		onClose: @escaping () -> Void
	)
	{
		self.interaction = interaction
		self.onRespond = onRespond
		self.onClose = onClose
		super.init(frame: .zero)
		dictation.onRecordingChanged =
		{
			[weak self] recording in
			self?.renderRecording(recording || self?.isFinalizingDictation == true)
		}
		dictation.onLevelChanged =
		{
			[weak self] level in
			self?.recordingView?.append(level: level)
		}
		dictation.onFinished =
		{
			[weak self] text in
			guard let self
			else
			{
				return
			}
			self.isFinalizingDictation = false
			self.applyDictation(text)
			self.renderRecording(false)
			if self
				.submitsDictation &&
				!(self.field?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
					.isEmpty ?? true)
			{
				self.submitQuestion()
			}
			self.submitsDictation = false
		}
		let box = NSBox()
		box.boxType = .custom
		box.borderColor = AppKitColorTokens.border
		box.fillColor = AppKitColorTokens.elevated
		box.cornerRadius = 20
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
				constant: 16
			),
			content.trailingAnchor.constraint(
				equalTo: box.trailingAnchor,
				constant: -16
			),
			content.topAnchor.constraint(
				equalTo: box.topAnchor,
				constant: 16
			),
			content.bottomAnchor.constraint(
				equalTo: box.bottomAnchor,
				constant: -16
			),
		])
		showQuestion()
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func viewWillMove(toSuperview newSuperview: NSView?)
	{
		if newSuperview == nil
		{
			dictation.cancel()
		}
		super.viewWillMove(toSuperview: newSuperview)
	}

	private func showQuestion()
	{
		dictation.cancel()
		isFinalizingDictation = false
		answerViews = []
		recordingView = nil
		footerSpacer = nil
		for view in content.arrangedSubviews
		{
			content.removeArrangedSubview(view)
			view.removeFromSuperview()
		}
		guard interaction.questions.indices.contains(index)
		else
		{
			return
		}
		let question = interaction.questions[index]
		let header = AppKitLayout.horizontalStack([])
		if !interaction.isBlocking
		{
			let icon = NSImageView(image: DesktopIcons.questionBubble())
			icon.contentTintColor = AppKitColorTokens.secondaryText
			icon.setAccessibilityElement(false)
			header.addArrangedSubview(icon)
		}
		if !interaction.isBlocking
		{
			let title = NSTextField(labelWithString: "Question")
			title.setTypographyRole(TypographyTokens.Text.body)
			title.textColor = AppKitColorTokens.secondaryText
			header.addArrangedSubview(title)
		}
		let spacer = NSView()
		spacer.setContentHuggingPriority(
			.defaultLow,
			for: .horizontal
		)
		header.addArrangedSubview(spacer)
		if interaction.questions.count > 1
		{
			let previous = DesktopStyledButton(
				title: "‹",
				presentation: .quiet,
				target: self,
				action: #selector(previousQuestion)
			)
			previous.isEnabled = index > 0
			previous.setAccessibilityLabel("Previous question")
			header.addArrangedSubview(previous)
			let position =
				NSTextField(labelWithString: "\(index + 1) of \(interaction.questions.count)")
			position.setTypographyRole(TypographyTokens.Interaction.detail)
			header.addArrangedSubview(position)
			let next = DesktopStyledButton(
				title: "›",
				presentation: .quiet,
				target: self,
				action: #selector(nextQuestion)
			)
			next.isEnabled = index + 1 < interaction.questions.count
			next.setAccessibilityLabel("Next question")
			header.addArrangedSubview(next)
		}
		let close = DesktopStyledButton(
			title: "×",
			presentation: .quiet,
			target: self,
			action: #selector(closeQuestion)
		)
		close.setAccessibilityLabel("Close question")
		header.addArrangedSubview(close)
		if interaction.isBlocking
		{
			let title = NSTextField(wrappingLabelWithString: question.question)
			title.setTypographyRole(TypographyTokens.Interaction.question)
			header.insertArrangedSubview(
				title,
				at: 0
			)
		}
		content.addArrangedSubview(header)
		header.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true

		if !interaction.isBlocking
		{
			let label = NSTextField(wrappingLabelWithString: question.question)
			label.setTypographyRole(TypographyTokens.Interaction.question)
			content.addArrangedSubview(label)
			label.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
		}
		for (optionIndex, option) in question.options.enumerated()
		{
			let recommended = interaction.isBlocking && option.label.hasSuffix(" (Recommended)")
			let displayLabel = recommended ? String(option.label.dropLast(" (Recommended)".count)) :
				option.label
			let row = DesktopMenuRow(content: .init(
				title: displayLabel,
				keycap: "\(optionIndex + 1)",
				keycapSelected: recommended,
				subtitle: interaction.isBlocking ? option.description : nil,
				suffix: recommended ? "Recommended" : "",
				suffixStyle: .badge
			))
			row.onInvoke =
			{
				[weak self] in self?.choose(option.label)
			}
			row.setAccessibilityLabel(option.label)
			content.addArrangedSubview(row)
			row.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
		}
		field = nil
		let footer = AppKitLayout.horizontalStack([])
		footer.distribution = .fill
		var freeTextRow: NSStackView?
		if question.options.isEmpty || question.allowsOther
		{
			let input: NSTextField = question.isSecret
				? NSSecureTextField() :
				DesktopTextField(centeredMultiline: TypographyTokens.Text.body)
			input.setTypographyRole(TypographyTokens.Text.body)
			input.placeholderString = question.options
				.isEmpty ? "Reply…" :
				(interaction
					.isBlocking ? "No, and tell ChatGPT what to do differently" :
					"Or write your own response")
			input.stringValue = answers[question.id] ?? ""
			input.delegate = self
			input.cell?.wraps = true
			input.cell?.isScrollable = false
			input.maximumNumberOfLines = 0
			input.setAccessibilityLabel("Answer for \(question.header)")
			if question.options.isEmpty
			{
				input.isBordered = false
				input.drawsBackground = false
				input.setContentHuggingPriority(
					.defaultLow,
					for: .horizontal
				)
				let row = AppKitLayout.horizontalStack(
					[input],
					spacing: 8
				)
				row.distribution = .fill
				let inputBox = NSBox()
				inputBox.boxType = .custom
				inputBox.borderColor = AppKitColorTokens.border
				inputBox.fillColor = AppKitColorTokens.elevated
				inputBox.cornerRadius = 10
				inputBox.contentView = row
				content.addArrangedSubview(inputBox)
				answerViews.append(inputBox)
				row.translatesAutoresizingMaskIntoConstraints = false
				NSLayoutConstraint.activate([
					inputBox.widthAnchor.constraint(equalTo: content.widthAnchor),
					row.leadingAnchor.constraint(
						equalTo: inputBox.leadingAnchor,
						constant: 12
					),
					row.trailingAnchor.constraint(
						equalTo: inputBox.trailingAnchor,
						constant: -4
					),
					row.topAnchor.constraint(
						equalTo: inputBox.topAnchor,
						constant: 6
					),
					row.bottomAnchor.constraint(
						equalTo: inputBox.bottomAnchor,
						constant: -6
					),
				])
				freeTextRow = row
			}
			else
			{
				do
				{
					let icon = NSImageView(image: DesktopIcons.image(.editPencil))
					icon.contentTintColor = AppKitColorTokens.secondaryText
					icon.setAccessibilityElement(false)
					footer.addArrangedSubview(icon)
					answerViews.append(icon)
				}
				input.isBordered = false
				input.drawsBackground = false
				input.setContentHuggingPriority(
					.defaultLow,
					for: .horizontal
				)
				footer.addArrangedSubview(input)
				answerViews.append(input)
			}
			field = input
			let height = input.heightAnchor.constraint(greaterThanOrEqualToConstant: 32)
			height.isActive = true
			inputHeight = height
			updateInputHeight()
		}
		let footerSpacer = NSView()
		footerSpacer.setContentHuggingPriority(
			.defaultLow,
			for: .horizontal
		)
		footerSpacer.isHidden = !question.options.isEmpty && field != nil
		footer.addArrangedSubview(footerSpacer)
		self.footerSpacer = footerSpacer
		if field != nil && !question.isSecret
		{
			let microphone = DesktopStyledButton(
				title: "",
				presentation: .quiet,
				target: self,
				action: #selector(toggleDictation)
			)
			microphone.image = NSImage(
				systemSymbolName: "mic",
				accessibilityDescription: nil
			)
			microphone.setAccessibilityLabel("Dictate answer")
			if let freeTextRow
			{
				freeTextRow.addArrangedSubview(microphone)
			}
			else
			{
				footer.addArrangedSubview(microphone)
			}
			dictationButton = microphone
			answerViews.append(microphone)
		}
		else
		{
			dictationButton = nil
		}
		if field != nil && !question.isSecret
		{
			let recording = QuestionRecordingView()
			recording.isHidden = true
			recording.onCancel =
			{
				[weak self] in self?.cancelDictation()
			}
			recording.onStop =
			{
				[weak self] in self?.finishDictation(submit: false)
			}
			recording.onAccept =
			{
				[weak self] in self?.finishDictation(submit: true)
			}
			content.addArrangedSubview(recording)
			recording.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
			recordingView = recording
		}
		let skip = DesktopStyledButton(
			title: "Skip",
			presentation: .secondary,
			target: self,
			action: #selector(skipQuestion)
		)
		footer.addArrangedSubview(skip)
		let primary = DesktopStyledButton(
			title: index + 1 == interaction.questions.count ? "Send" : "Next",
			presentation: .primary,
			target: self,
			action: #selector(submitQuestion)
		)
		primary.isEnabled = !(answers[question.id] ?? "").isEmpty
		hidesEmptyPrimary = interaction.isBlocking && !question.options.isEmpty
		primary.isHidden = hidesEmptyPrimary && !primary.isEnabled
		footer.addArrangedSubview(primary)
		primaryButton = primary
		content.addArrangedSubview(footer)
		footer.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
		onContentSizeChanged?()
	}

	func controlTextDidChange(_ notification: Notification)
	{
		let value = (field?.currentEditor() as? NSTextView)?.string ?? field?.stringValue ?? ""
		primaryButton?.isEnabled = !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		primaryButton?.isHidden = hidesEmptyPrimary && (primaryButton?.isEnabled == false)
		updateInputHeight()
	}

	func control(
		_ control: NSControl,
		textView: NSTextView,
		doCommandBy commandSelector: Selector
	) -> Bool
	{
		guard control === field, commandSelector == #selector(NSResponder.insertNewline(_:)),
				NSEvent.modifierFlags.contains(.shift)
		else
		{
			return false
		}
		textView.insertText(
			"\n",
			replacementRange: textView.selectedRange()
		)
		return true
	}

	private func updateInputHeight()
	{
		guard let field, let inputHeight, let font = field.font
		else
		{
			return
		}
		let width = max(
			field.bounds.width - 16,
			180
		)
		let value = (field.currentEditor() as? NSTextView)?.string ?? field.stringValue
		let size = (value as NSString).boundingRect(
			with: NSSize(
				width: width,
				height: .greatestFiniteMagnitude
			),
			options: [.usesLineFragmentOrigin, .usesFontLeading],
			attributes: [.font: font]
		).height
		let height = max(
			32,
			ceil(size) + 16
		)
		if inputHeight.constant != height
		{
			inputHeight.constant = height
			field.needsLayout = true
			onContentSizeChanged?()
		}
		else
		{
			field.needsLayout = true
		}
	}

	private func saveField()
	{
		guard let field, interaction.questions.indices.contains(index)
		else
		{
			return
		}
		let text = (field.currentEditor() as? NSTextView)?.string ?? field.stringValue
		let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
		if !value.isEmpty
		{
			answers[interaction.questions[index].id] = value
		}
		else
		{
			answers.removeValue(forKey: interaction.questions[index].id)
		}
	}

	private func choose(_ answer: String)
	{
		isFinalizingDictation = false
		submitsDictation = false
		dictation.cancel()
		answers[interaction.questions[index].id] = answer
		advance()
	}

	private func advance()
	{
		if index + 1 < interaction.questions.count
		{
			index += 1
			showQuestion()
		}
		else
		{
			onRespond(.answers(answers.mapValues
				{
					[$0]
				}))
		}
	}

	private func renderRecording(_ active: Bool)
	{
		for view in answerViews
		{
			view.isHidden = active
		}
		recordingView?.isHidden = !active
		footerSpacer?
			.isHidden = !active && !(interaction.questions[index].options.isEmpty || field == nil)
		primaryButton?
			.isEnabled = !active &&
			!(field?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
		primaryButton?.isHidden = hidesEmptyPrimary && primaryButton?.isEnabled == false
		onContentSizeChanged?()
	}

	private func applyDictation(_ text: String)
	{
		guard let field
		else
		{
			return
		}
		let value = text
			.isEmpty ? dictationDraft :
			(dictationDraft.isEmpty ? text : dictationDraft + " " + text)
		field.stringValue = value
		(field.currentEditor() as? NSTextView)?.string = value
		updateInputHeight()
	}

	private func cancelDictation()
	{
		isFinalizingDictation = false
		submitsDictation = false
		dictation.cancel()
		applyDictation("")
		renderRecording(false)
	}

	private func finishDictation(submit: Bool)
	{
		if isFinalizingDictation
		{
			submitsDictation = submit
			return
		}
		guard dictation.isRecording
		else
		{
			return
		}
		submitsDictation = submit
		isFinalizingDictation = true
		dictation.stop()
	}

	@objc private func toggleDictation()
	{
		guard !dictation.isRecording && !isFinalizingDictation
		else
		{
			return
		}
		dictationDraft = (field?.currentEditor() as? NSTextView)?.string ?? field?.stringValue ?? ""
		window?.makeFirstResponder(nil)
		recordingView?.reset()
		dictation.start
		{
			[weak self] text in self?.applyDictation(text)
		}
	}

	@objc private func submitQuestion()
	{
		dictation.cancel(); saveField(); advance()
	}
	@objc private func skipQuestion()
	{
		dictation.cancel(); answers.removeValue(forKey: interaction.questions[index].id); advance()
	}
	@objc private func previousQuestion()
	{
		saveField(); index -= 1; showQuestion()
	}
	@objc private func nextQuestion()
	{
		saveField(); index += 1; showQuestion()
	}
	@objc private func closeQuestion()
	{
		dictation.cancel(); onClose()
	}
}
