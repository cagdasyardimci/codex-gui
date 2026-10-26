import AppKit

/// Complete stack-result search surface, including query header and result viewport.
@MainActor
final class DesktopSearchOverlayView: NSView
{
	enum Presentation
	{
		case chats, changedFiles, attachments
	}
	enum MessagePresentation
	{
		case section, status, nativeStatus
	}
	let scrollView: NSScrollView
	private let presentation: Presentation

	init(
		presentation: Presentation,
		search: NSSearchField,
		results: NSStackView
	)
	{
		self.presentation = presentation
		results.orientation = .vertical
		results.alignment = .leading
		results.spacing = presentation == .attachments ? 2 : 0
		if presentation == .chats
		{
			scrollView = AppKitLayout.scrollableContent(
				results,
				inset: 0
			)
			scrollView.drawsBackground = false
		}
		else
		{
			scrollView = NSScrollView()
			scrollView.hasVerticalScroller = true
			results.translatesAutoresizingMaskIntoConstraints = false
			scrollView.documentView = results
			results.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
				.isActive = true
			if presentation == .changedFiles
			{
				scrollView.autohidesScrollers = true
				scrollView.drawsBackground = false
			}
		}
		super.init(frame: .zero)
		let inset: CGFloat = presentation == .chats ? 12 : 8
		let spacing: CGFloat = presentation == .chats ? 12 : (presentation == .changedFiles ? 8 : 6)
		let header: NSView
		if presentation == .changedFiles
		{
			let icon = NSImageView(image: DesktopIcons.image(.search))
			icon.contentTintColor = .secondaryLabelColor
			icon.imageScaling = .scaleProportionallyDown
			icon.setAccessibilityElement(false)
			header = AppKitLayout.horizontalStack(
				[icon, search],
				spacing: 8
			)
			NSLayoutConstraint.activate([
				header.heightAnchor.constraint(equalToConstant: 32),
				icon.widthAnchor.constraint(equalToConstant: 16),
				icon.heightAnchor.constraint(equalToConstant: 16),
				search.heightAnchor.constraint(equalToConstant: 20),
			])
		}
		else
		{
			header = search
			if presentation == .chats
			{
				search.heightAnchor.constraint(equalToConstant: 32).isActive = true
			}
		}
		let layout = AppKitLayout.verticalStack(
			[header, scrollView],
			spacing: spacing
		)
		AppKitLayout.pin(
			layout,
			to: self,
			inset: inset
		)
		NSLayoutConstraint.activate([
			header.widthAnchor.constraint(equalTo: layout.widthAnchor),
			scrollView.widthAnchor.constraint(equalTo: layout.widthAnchor),
			scrollView.bottomAnchor.constraint(equalTo: layout.bottomAnchor),
		])
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	static func message(
		_ text: String,
		presentation: MessagePresentation
	) -> NSView
	{
		let label = NSTextField(labelWithString: text)
		if presentation != .nativeStatus
		{
			label.textColor = .secondaryLabelColor
		}
		guard presentation == .section
		else
		{
			return label
		}
		label.font = .systemFont(ofSize: 12)
		let container = NSView()
		AppKitLayout.pin(
			label,
			to: container,
			inset: 8
		)
		container.heightAnchor.constraint(equalToConstant: 32).isActive = true
		return container
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		if presentation != .attachments
		{
			AppKitColorTokens.searchPanel.setFill()
			bounds.fill()
		}
	}
}
