import AppKit

/// Complete native search-sheet presentation with owned inputs, messages, actions and sizing.
@MainActor
final class DesktopSearchSheetView: NSView
{
	enum Presentation
	{
		case commands, messages
	}

	let query = DesktopSearchField()
	let table = NSTableView()
	var onClose: (() -> Void)?
	var onLoadMore: (() -> Void)?
	var explanation: String?
	{
		didSet
		{
			explanationLabel.stringValue = explanation ?? ""
			explanationLabel.isHidden = explanation == nil
		}
	}
	var emptyMessage = "No matching commands"
	{
		didSet
		{
			emptyLabel.stringValue = emptyMessage
		}
	}
	var hasResults = false
	{
		didSet
		{
			emptyLabel.isHidden = hasResults
		}
	}
	var scopeText = ""
	{
		didSet
		{
			scopeLabel.stringValue = scopeText
		}
	}
	var statusText = ""
	{
		didSet
		{
			statusLabel.stringValue = statusText
			statusLabel.isHidden = statusText.isEmpty
		}
	}
	var canLoadMore = false
	{
		didSet
		{
			loadMoreButton.isHidden = !canLoadMore
		}
	}
	var isLoading = false
	{
		didSet
		{
			loadMoreButton.isEnabled = !isLoading
		}
	}
	private let presentation: Presentation
	private let explanationLabel = NSTextField(wrappingLabelWithString: "")
	private let emptyLabel = NSTextField(labelWithString: "No matching commands")
	private let scopeLabel = NSTextField(wrappingLabelWithString: "")
	private let statusLabel = NSTextField(labelWithString: "")
	private let loadMoreButton = DesktopActionButton(
		title: "Load More History",
		presentation: .nativeDefault
	)
	private let closeButton = DesktopActionButton(
		title: "Close",
		presentation: .nativeDefault
	)

	init(presentation: Presentation)
	{
		self.presentation = presentation
		super.init(frame: .zero)
		let scroll = NSScrollView()
		scroll.documentView = table
		scroll.hasVerticalScroller = true
		table.headerView = nil
		closeButton.onAction =
		{
			[weak self] in self?.onClose?()
		}
		loadMoreButton.onAction =
		{
			[weak self] in self?.onLoadMore?()
		}
		let views: [NSView]
		let minimumResultsHeight: CGFloat
		let columnID: String
		switch presentation
		{
		case .commands:
			explanationLabel.textColor = .secondaryLabelColor
			explanationLabel.font = .systemFont(ofSize: 12)
			explanationLabel.isHidden = true
			emptyLabel.textColor = .secondaryLabelColor
			closeButton.setAccessibilityLabel("Close command palette")
			table.rowHeight = 42
			table.setAccessibilityLabel("Matching projects, conversations, and actions")
			views = [explanationLabel, query, scroll, emptyLabel, closeButton]
			minimumResultsHeight = 220
			columnID = "command"
		case .messages:
			scopeLabel.textColor = .secondaryLabelColor
			scopeLabel.font = .systemFont(ofSize: 11)
			scopeLabel.setAccessibilityLabel("Message search scope and history limits")
			statusLabel.textColor = .secondaryLabelColor
			statusLabel.setAccessibilityLabel("Message history loading status")
			statusLabel.isHidden = true
			loadMoreButton
				.setAccessibilityLabel("Load more conversation history into message search")
			loadMoreButton.isHidden = true
			closeButton.setAccessibilityLabel("Close message search")
			table.rowHeight = 54
			table.setAccessibilityLabel("Matching messages")
			views = [AppKitLayout.title("Search Messages"),
						query,
						scopeLabel,
						statusLabel,
						scroll,
						loadMoreButton,
						closeButton]
			minimumResultsHeight = 280
			columnID = "messageHit"
		}
		table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier(columnID)))
		let stack = AppKitLayout.verticalStack(views)
		AppKitLayout.pin(
			stack,
			to: self
		)
		NSLayoutConstraint.activate([
			scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
			scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: minimumResultsHeight),
		])
		if presentation == .messages
		{
			query.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
			scopeLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func resize(
		window: NSWindow,
		relativeTo parent: NSWindow
	)
	{
		let size: NSSize
		switch presentation
		{
		case .commands:
			size = NSSize(
				width: min(
					560,
					max(
						400,
						parent.frame.width - 80
					)
				),
				height: explanation == nil ? 360 : 420
			)
		case .messages:
			size = NSSize(
				width: min(
					680,
					max(
						440,
						parent.frame.width - 80
					)
				),
				height: 480
			)
		}
		window.setContentSize(size)
		layoutSubtreeIfNeeded()
		let height = max(
			size.height,
			fittingSize.height
		)
		if height > size.height
		{
			window.setContentSize(NSSize(
				width: size.width,
				height: height
			))
		}
	}
}
