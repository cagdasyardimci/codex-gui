import AppKit

/// New comments use a single-line capsule; saved comments open the multiline editor.
@MainActor
final class ImageCommentEditor: DesktopSurface, NSTextViewDelegate, NSTextFieldDelegate
{
	let textView = NSTextView()
	let inputField: DesktopTextField?
	let saveButton: DesktopActionButton
	let cancelButton = DesktopActionButton(
		title: "Cancel",
		presentation: .secondary
	)
	let deleteButton = DesktopActionButton(
		icon: .trash,
		label: "Delete comment"
	)
	{
	}
	var onSave: ((String) -> Void)?
	var onCancel: (() -> Void)?
	var onDelete: (() -> Void)?
	private let existing: Bool
	private let fieldEditorStyle = ThemeFieldEditorStyle()
	private weak var borrowedFieldEditor: NSText?
	private var colorObservation: ThemeColorObservation?

	var preferredHeight: CGFloat
	{
		existing ? 120 : 44
	}
	var focusView: NSView
	{
		if let inputField
		{
			return inputField
		}
		return textView
	}
	private var commentText: String
	{
		inputField?.stringValue ?? textView.string
	}

	init(
		text: String,
		existing: Bool
	)
	{
		self.existing = existing
		inputField = existing ? nil : DesktopTextField(singleLine: TypographyTokens.Text.body)
		saveButton = DesktopActionButton(
			title: existing ? "Save" : "",
			presentation: existing ? .primary : .imageCommentSubmit
		)
		super.init(
			AppKitColorTokens.imageAnnotationSurface,
			cornerRadius: 22,
			shadows: existing ? ShadowTokens.popover : []
		)
		// Annotation editors share the overlay dark profile, including native field editors
		// and action controls, so their contrast pair stays coherent over image artwork.
		appearance = NSAppearance(named: .darkAqua)
		frame = NSRect(
			x: 0,
			y: 0,
			width: 294,
			height: preferredHeight
		)
		if let inputField
		{
			configureInput(
				inputField,
				text: text
			)
		}
		else
		{
			configureExistingComment(text: text)
		}
		saveButton.onAction =
		{
			[weak self] in self?.save()
		}
		cancelButton.onAction =
		{
			[weak self] in self?.onCancel?()
		}
		deleteButton.onAction =
		{
			[weak self] in self?.onDelete?()
		}
		for button in [saveButton, cancelButton, deleteButton]
		{
			button.keyboardFocusPolicy = .dialog
		}
		colorObservation = ThemeColorObservation(view: self)
		{
			[weak self] in
			self?.refreshColors()
		}
		refreshColors()
		updateSubmission()
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	private func configureInput(
		_ field: DesktopTextField,
		text: String
	)
	{
		field.stringValue = text
		field.isEditable = true
		field.isSelectable = true
		field.isBezeled = false
		field.isBordered = false
		field.drawsBackground = false
		field.focusRingType = .none
		field.usesSingleLineMode = true
		field.cell?.isScrollable = true
		field.delegate = self
		field.setAccessibilityLabel("Add comment")
		field.setTypographyRole(
			TypographyTokens.Text.body,
			onUpdate:
			{
				[weak self] in
				self?.refreshColors()
			}
		)
		field.setContentHuggingPriority(
			.defaultLow,
			for: .horizontal
		)
		field.heightAnchor.constraint(equalToConstant: 28).isActive = true
		saveButton.symbol = .arrowUp
		saveButton.setAccessibilityLabel("Add comment")
		cancelButton.isHidden = true
		deleteButton.isHidden = true
		let row = AppKitLayout.horizontalStack(
			[field, saveButton],
			spacing: 8
		)
		row.translatesAutoresizingMaskIntoConstraints = false
		addSubview(row)
		NSLayoutConstraint.activate([
			row.leadingAnchor.constraint(
				equalTo: leadingAnchor,
				constant: 16
			),
			row.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -8
			),
			row.topAnchor.constraint(
				equalTo: topAnchor,
				constant: 8
			),
			row.bottomAnchor.constraint(
				equalTo: bottomAnchor,
				constant: -8
			)
		])
	}

	private func configureExistingComment(text: String)
	{
		textView.string = text
		textView.isRichText = false
		textView.isAutomaticQuoteSubstitutionEnabled = false
		textView.isAutomaticDashSubstitutionEnabled = false
		textView.textContainerInset = .zero
		textView.textContainer?.lineFragmentPadding = 0
		textView.isHorizontallyResizable = false
		textView.isVerticallyResizable = true
		textView.autoresizingMask = [.width]
		textView.textContainer?.widthTracksTextView = true
		textView.setTypographyRole(TypographyTokens.Text.paragraph)
		textView.setAccessibilityLabel("Comment")
		textView.delegate = self
		let scroll = NSScrollView()
		scroll.drawsBackground = false
		scroll.hasVerticalScroller = true
		scroll.autohidesScrollers = true
		scroll.documentView = textView
		textView.frame = NSRect(
			x: 0,
			y: 0,
			width: 262,
			height: 60
		)
		let actions = AppKitLayout.horizontalStack(
			[deleteButton, NSView(), cancelButton, saveButton],
			spacing: 6
		)
		for child in [scroll, actions]
		{
			child.translatesAutoresizingMaskIntoConstraints = false
			addSubview(child)
		}
		NSLayoutConstraint.activate([
			scroll.topAnchor.constraint(
				equalTo: topAnchor,
				constant: 10
			),
			scroll.leadingAnchor.constraint(
				equalTo: leadingAnchor,
				constant: 16
			),
			scroll.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -16
			),
			scroll.bottomAnchor.constraint(
				equalTo: actions.topAnchor,
				constant: -10
			),
			actions.leadingAnchor.constraint(
				equalTo: leadingAnchor,
				constant: 8
			),
			actions.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -12
			),
			actions.bottomAnchor.constraint(
				equalTo: bottomAnchor,
				constant: -10
			)
		])
	}

	private func refreshColors()
	{
		effectiveAppearance.performAsCurrentDrawingAppearance
		{
			if let inputField
			{
				inputField.textColor = AppKitColorTokens.primaryText
				var attributes = AppKitFontResolver.textAttributes(
					TypographyTokens.Text.body,
					font: AppKitFontResolver.font(
						TypographyTokens.Text.body,
						appearance: effectiveAppearance
					)
				)
				attributes[.foregroundColor] = AppKitColorTokens.secondaryText
				inputField.placeholderAttributedString = NSAttributedString(
					string: "Add a comment…",
					attributes: attributes
				)
				if let editor = inputField.currentEditor()
				{
					fieldEditorStyle.apply(
						to: editor,
						in: self
					)
				}
			}
			else
			{
				textView.backgroundColor = AppKitColorTokens.imageAnnotationSurface
				textView.textColor = AppKitColorTokens.primaryText
				textView.insertionPointColor = AppKitColorTokens.primaryText
				textView.selectedTextAttributes = [
					.backgroundColor: AppKitColorTokens.selectionBackground,
					.foregroundColor: AppKitColorTokens.primaryText
				]
			}
		}
	}

	private func updateSubmission()
	{
		let hasText = !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		saveButton.isEnabled = hasText
		if !existing
		{
			saveButton.isHidden = !hasText
		}
	}

	func textDidChange(_ notification: Notification)
	{
		updateSubmission()
	}
	func controlTextDidChange(_ notification: Notification)
	{
		updateSubmission()
	}

	func controlTextDidBeginEditing(_ notification: Notification)
	{
		if let editor = inputField?.currentEditor()
		{
			borrowedFieldEditor = editor
			fieldEditorStyle.apply(
				to: editor,
				in: self
			)
		}
	}

	func controlTextDidEndEditing(_ notification: Notification)
	{
		if let borrowedFieldEditor
		{
			fieldEditorStyle.restore(borrowedFieldEditor)
		}
		borrowedFieldEditor = nil
	}

	@discardableResult
	func save() -> Bool
	{
		let editor = inputField?.currentEditor() as? NSTextView ?? (existing ? textView : nil)
		guard editor?.hasMarkedText() != true
		else
		{
			return false
		}
		inputField?.validateEditing()
		let text = commentText
		guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		else
		{
			return false
		}
		onSave?(text)
		return true
	}

	func control(
		_ control: NSControl,
		textView: NSTextView,
		doCommandBy commandSelector: Selector
	) -> Bool
	{
		if commandSelector == #selector(NSResponder.insertNewline(_:))
		{
			guard !textView.hasMarkedText()
			else
			{
				return false
			}
			_ = save()
			return true
		}
		return handleCancel(commandSelector)
	}

	func textView(
		_ textView: NSTextView,
		doCommandBy commandSelector: Selector
	) -> Bool
	{
		handleCancel(commandSelector)
	}

	private func handleCancel(_ command: Selector) -> Bool
	{
		guard command == #selector(NSResponder.cancelOperation(_:))
		else
		{
			return false
		}
		onCancel?()
		return true
	}
}
