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
	static let chatPreferredSize = NSSize(
		width: 768,
		height: 504
	)
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
		let spacing: CGFloat = presentation == .chats ? 0 : (presentation == .changedFiles ? 8 : 6)
		let header: NSView
		if presentation == .changedFiles
		{
			let icon = NSImageView(image: DesktopIcons.image(.search))
			icon.contentTintColor = AppKitColorTokens.secondaryText
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
		else if presentation == .chats
		{
			header = NSView()
			AppKitLayout.pin(
				search,
				to: header,
				inset: 0
			)
			search.heightAnchor.constraint(equalToConstant: 46).isActive = true
			let divider = DesktopSurface(AppKitColorTokens.subtleEdge)
			divider.translatesAutoresizingMaskIntoConstraints = false
			header.addSubview(divider)
			NSLayoutConstraint.activate([
				divider.leadingAnchor.constraint(equalTo: header.leadingAnchor),
				divider.trailingAnchor.constraint(equalTo: header.trailingAnchor),
				divider.bottomAnchor.constraint(equalTo: header.bottomAnchor),
				divider.heightAnchor.constraint(equalToConstant: 1)
			])
		}
		else
		{
			header = search
		}
		let layout = AppKitLayout.verticalStack(
			[header, scrollView],
			spacing: spacing
		)
		AppKitLayout.pin(
			layout,
			to: self,
			insets: presentation == .chats ? NSEdgeInsets(
				top: 5,
				left: 1,
				bottom: 4,
				right: 1
			) :
				NSEdgeInsets(
					top: 8,
					left: 8,
					bottom: 8,
					right: 8
				)
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
			label.textColor = AppKitColorTokens.secondaryText
		}
		guard presentation == .section
		else
		{
			return label
		}
		label.setTypographyRole(TypographyTokens.Search.section)
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
