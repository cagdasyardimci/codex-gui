import AppKit

/// Owns the temporary text field and actions for one inline revision.
@MainActor
final class TranscriptPromptEditor: DesktopSurface, NSTextViewDelegate
{
	static let rowHeight: CGFloat = 112
	let textView = NSTextView()
	private let send = DesktopActionButton(
		title: "Send",
		presentation: .primary
	)
	private let cancel = DesktopActionButton(
		title: "Cancel",
		presentation: .secondary
	)
	private let original: String
	private let allowsEmptyText: Bool
	var canSend: (() -> Bool)?
	var onSend: ((String) -> WorkspaceOperationHandle?)?
	private var isSubmitting = false
	var onCancel: (() -> Void)?

	init(
		text: String,
		allowsEmptyText: Bool
	)
	{
		original = text
		self.allowsEmptyText = allowsEmptyText
		super.init(
			AppKitColorTokens.userBubble,
			cornerRadius: ShapeTokens.Transcript.userRadius
		)
		textView.isRichText = false
		textView.importsGraphics = false
		textView.allowsUndo = true
		textView.isAutomaticQuoteSubstitutionEnabled = false
		textView.isAutomaticDashSubstitutionEnabled = false
		textView.isHorizontallyResizable = false
		textView.isVerticallyResizable = true
		textView.autoresizingMask = [.width]
		textView.textContainerInset = .zero
		textView.textContainer?.widthTracksTextView = true
		textView.textContainer?.lineFragmentPadding = 0
		textView.drawsBackground = false
		textView.textColor = AppKitColorTokens.primaryText
		textView.insertionPointColor = AppKitColorTokens.primaryText
		textView.setTypographyRole(TypographyTokens.Text.paragraph)
		textView.setAccessibilityLabel("Edit message")
		textView.string = text
		textView.setSelectedRange(NSRange(
			location: text.utf16.count,
			length: 0
		))
		textView.delegate = self

		let scroll = NSScrollView()
		scroll.drawsBackground = false
		scroll.hasVerticalScroller = true
		scroll.autohidesScrollers = true
		textView.frame.size.height = 52
		scroll.documentView = textView
		let actions = AppKitLayout.horizontalStack(
			[NSView(), cancel, send],
			spacing: 6
		)
		let column = NSStackView(views: [scroll, actions])
		column.orientation = .vertical
		column.alignment = .width
		column.spacing = 8
		addSubview(column)
		AppKitLayout.pin(
			column,
			to: self,
			inset: 12
		)

		send.onAction =
		{
			[weak self] in self?.submit()
		}
		cancel.onAction =
		{
			[weak self] in self?.onCancel?()
		}
		refreshSend()
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func refreshSend()
	{
		cancel.isEnabled = !isSubmitting
		let revision = textView.string
		send.isEnabled = !isSubmitting && revision != original
			&&
			(allowsEmptyText || !revision.trimmingCharacters(in: .whitespacesAndNewlines)
				.isEmpty)
			&& canSend?() == true
	}

	func textDidChange(_ notification: Notification)
	{
		refreshSend()
	}

	func textView(
		_ textView: NSTextView,
		doCommandBy selector: Selector
	) -> Bool
	{
		guard selector == #selector(NSResponder.cancelOperation(_:)), !textView.hasMarkedText()
		else
		{
			return false
		}
		if !isSubmitting
		{
			onCancel?()
		}
		return true
	}

	private func submit()
	{
		refreshSend()
		guard send.isEnabled, !textView.hasMarkedText()
		else
		{
			return
		}
		guard let operation = onSend?(textView.string)
		else
		{
			refreshSend()
			return
		}
		isSubmitting = true
		refreshSend()
		Task
		{
			[weak self] in
			_ = await operation.wait()
			self?.isSubmitting = false
			self?.refreshSend()
		}
	}
}
