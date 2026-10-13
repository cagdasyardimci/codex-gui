import AppKit

@MainActor
final class PinnedSummaryViewController: NSViewController
{
	var onNavigate: ((ContextPanelRequest) -> Void)?
	var onContentHeightChange: (() -> Void)?
	private var presentation: PinnedSummaryPresentation?
	private var sourcesExpanded = true
	private weak var sourcesDisclosureButton: NSButton?
	private let stack = NSStackView()
	private var thumbnailTasks: [Task<Void, Never>] = []
	private var renderGeneration = 0
	private var actions: [NSButton: ContextPanelRequest] = [:]

	private typealias Layout = LayoutTokens.Summary

	var preferredContentHeight: CGFloat
	{
		_ = view
		return ceil(stack.fittingSize.height)
	}

	override func loadView()
	{
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = 8
		view = makeScrollView()
	}

	func render(_ presentation: PinnedSummaryPresentation)
	{
		guard self.presentation != presentation
		else
		{
			return
		}
		if self.presentation?.owner != presentation.owner
		{
			sourcesExpanded = true
		}
		self.presentation = presentation
		renderContent(presentation)
	}

	private func renderContent(_ presentation: PinnedSummaryPresentation)
	{
		_ = view
		clearRenderedContent()

		let heading = header(presentation.contextName)
		heading.heightAnchor.constraint(equalToConstant: 24).isActive = true
		add(heading)
		addChanges(presentation)
		addDivider()
		addAgents(presentation)
		addSources(presentation)
	}

	private func clearRenderedContent()
	{
		renderGeneration += 1
		thumbnailTasks.forEach
		{
			$0.cancel()
		}
		thumbnailTasks.removeAll()
		actions.removeAll()
		stack.arrangedSubviews.forEach
		{
			stack.removeArrangedSubview($0)
			$0.removeFromSuperview()
		}
	}

	private func addChanges(_ presentation: PinnedSummaryPresentation)
	{
		let row = makeChangesRow(presentation)
		add(row)
		if let message = presentation.sections.changes.message
		{
			add(statusLabel(message))
		}
	}

	private func makeChangesRow(_ presentation: PinnedSummaryPresentation) -> NSStackView
	{
		let changes = button(
			"Changes",
			symbol: nil,
			destination: .changes
		)
		changes.contentTintColor = .labelColor
		// Keep the Changes title readable beside the icon and optional totals.
		let readableWidth = ceil(changes.attributedTitle.size().width) + 4
		changes.widthAnchor.constraint(greaterThanOrEqualToConstant: readableWidth).isActive = true
		changes.setContentCompressionResistancePriority(
			.defaultHigh,
			for: .horizontal
		)
		let spacer = NSView()
		spacer.setContentHuggingPriority(
			NSLayoutConstraint.Priority(1),
			for: .horizontal
		)
		spacer.setContentCompressionResistancePriority(
			NSLayoutConstraint.Priority(1),
			for: .horizontal
		)
		let row = AppKitLayout.horizontalStack(
			[
				iconButton(
					PinnedSummaryIcons.image(.changes),
					title: "Changes",
					destination: .changes
				),
				changes,
				spacer
			],
			spacing: 12
		)
		row.heightAnchor.constraint(equalToConstant: Layout.contentRowHeight).isActive = true
		if let totals = presentation.sections.changes.value
		{
			let additions = label(
				"+\(formattedCount(totals.additions))",
				color: .systemGreen
			)
			additions.setAccessibilityLabel("\(totals.additions) additions")
			let deletions = label(
				"-\(formattedCount(totals.deletions))",
				color: .systemRed
			)
			deletions.setAccessibilityLabel("\(totals.deletions) deletions")
			row.addArrangedSubview(additions)
			row.addArrangedSubview(deletions)
			row.setCustomSpacing(
				4,
				after: additions
			)
		}
		return row
	}

	private func formattedCount(_ value: Int) -> String
	{
		let formatter = NumberFormatter()
		formatter.numberStyle = .decimal
		formatter.locale = Locale(identifier: "en_US")
		return formatter.string(from: NSNumber(value: value)) ?? String(value)
	}

	private func addAgents(_ presentation: PinnedSummaryPresentation)
	{
		let section = presentation.sections.agents
		// Unavailable optional data is hidden; never turn an absent provider into a zero count.
		if case .unavailable = section
		{
			return
		}
		let heading = button(
			"Subagents",
			symbol: nil,
			destination: .subagents
		)
		heading.attributedTitle = attributedTitle(
			"Subagents",
			color: .secondaryLabelColor
		)
		addSectionHeading(heading)
		if let agents = section.value
		{
			let completed = "\(agents.completedCount) done"
			let text = agents.runningCount > 0
				? completed + " · \(agents.runningCount) running" : completed
			let summary = button(
				text,
				symbol: nil,
				destination: .subagents
			)
			summary.setAccessibilityLabel(text + ". " + agents.aggregationDescription)
			add(agentRow(
				summary,
				agents: presentation.agentPreviews
			))
		}
		if let message = section.message
		{
			add(statusLabel(message))
		}
		addDivider()
	}

	private func addSources(_ presentation: PinnedSummaryPresentation)
	{
		addSectionHeading(makeSourcesHeading(presentation))
		guard sourcesExpanded
		else
		{
			return
		}
		for source in presentation.sourcePreviews.prefix(3)
		{
			let row = sourceRow(
				source,
				presentation: presentation
			)
			add(row)
			stack.setCustomSpacing(
				2,
				after: row
			)
		}
		if presentation.sections.sources.value?.isEmpty == true
		{
			add(label("No sources"))
		}
		if let message = presentation.sections.sources.message
		{
			add(statusLabel(message))
		}
		add(makeViewAllSourcesRow())
	}

	private func makeSourcesHeading(_ presentation: PinnedSummaryPresentation) -> NSStackView
	{
		let count = presentation.sections.sources.value.map
		{
			Set($0.map(\.id)).count
		}
		let title = !sourcesExpanded ? count.map
		{
			"Sources · \(formattedCount($0))"
		} ?? "Sources" : "Sources"
		let sources = DesktopAttributedTitleButton(
			title: title,
			target: self,
			action: #selector(toggleSources(_:))
		)
		sources.isBordered = false
		sources.alignment = .left
		sources.font = .systemFont(ofSize: 13)
		sources.attributedTitle = attributedTitle(
			title,
			color: .secondaryLabelColor
		)
		sources.contentTintColor = .secondaryLabelColor
		sources.image = sourcesExpanded ? nil : DesktopIcons.image(.chevronRight)
		sources.imagePosition = .imageTrailing
		sources.imageScaling = .scaleProportionallyDown
		sources.setAccessibilityIdentifier("pinned-summary-sources-disclosure")
		sources.setAccessibilityLabel(title)
		sources.setAccessibilityValue(sourcesExpanded ? "Expanded" : "Collapsed")
		sources.toolTip = sourcesExpanded ? "Collapse sources" : "Expand sources"
		sourcesDisclosureButton = sources
		let plus = NSButton(
			title: "Add sources",
			target: nil,
			action: nil
		)
		plus.isBordered = false
		plus.isEnabled = false
		plus.image = DesktopIcons.image(.plus)
		plus.imagePosition = .imageOnly
		plus.contentTintColor = .tertiaryLabelColor
		plus.widthAnchor.constraint(equalToConstant: 18).isActive = true
		plus.heightAnchor.constraint(equalToConstant: 18).isActive = true
		plus.setAccessibilityIdentifier("pinned-summary-add-sources")
		plus.setAccessibilityLabel("Add sources")
		plus.toolTip = "Add sources"
		return AppKitLayout.horizontalStack(
			[sources, NSView(), plus],
			spacing: 8
		)
	}

	private func makeViewAllSourcesRow() -> NSStackView
	{
		let all = button(
			"View all",
			symbol: nil,
			destination: .sources
		)
		all.attributedTitle = attributedTitle(
			"View all",
			color: .tertiaryLabelColor
		)
		let icon = iconButton(
			DesktopIcons.image(.addSources),
			title: "View all",
			destination: .sources
		)
		icon.contentTintColor = .tertiaryLabelColor
		let row = AppKitLayout.horizontalStack(
			[icon, all],
			spacing: 12
		)
		row.heightAnchor.constraint(equalToConstant: Layout.contentRowHeight).isActive = true
		return row
	}

	private func sourceRow(
		_ source: PinnedSummaryPresentation.SourcePreview,
		presentation: PinnedSummaryPresentation
	) -> NSView
	{
		let imageView = NSImageView()
		let iconSize = Layout.sourceIconSize
		imageView.image = sourceImage(for: source)
		imageView.contentTintColor = .secondaryLabelColor
		imageView.imageScaling = .scaleProportionallyUpOrDown
		imageView.setAccessibilityElement(false)
		imageView.widthAnchor.constraint(equalToConstant: iconSize).isActive = true
		imageView.heightAnchor.constraint(equalToConstant: iconSize).isActive = true

		let text: NSView
		if let request = presentation.sourceRequest(for: source)
		{
			let control = button(
				source.label,
				symbol: nil,
				destination: .sources
			)
			actions[control] = request
			control.attributedTitle = attributedTitle(
				source.label,
				color: .secondaryLabelColor
			)
			text = control
		}
		else
		{
			// A readable descriptor is useful even without individual resource navigation.
			let name = label(source.label)
			name.setAccessibilityLabel(source.label)
			name.toolTip = source.label
			text = name
		}
		text.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		let row = AppKitLayout.horizontalStack(
			[imageView, text],
			spacing: Layout.sourceRowSpacing
		)
		text.widthAnchor.constraint(
			equalTo: row.widthAnchor,
			constant: -iconSize - Layout.sourceRowSpacing
		).isActive = true
		row.heightAnchor.constraint(equalToConstant: Layout.contentRowHeight).isActive = true
		if let path = source.thumbnailPath
		{
			let owner = presentation.owner
			let generation = renderGeneration
			thumbnailTasks.append(Task
			{
				[weak self, weak imageView] in
				let data = await SourceThumbnailLoader.load(path: path)
				guard !Task.isCancelled, self?.presentation?.owner == owner,
						self?.renderGeneration == generation,
						let imageView, let data, let image = NSImage(data: data)
				else
				{
					return
				}
				imageView.image = image
			})
		}
		return row
	}

	private func sourceImage(for source: PinnedSummaryPresentation.SourcePreview) -> NSImage?
	{
		if let icon = source.icon
		{
			return DesktopIcons.image(icon)
		}
		return switch source.kind
		{
		case .tool: DesktopIcons.image(.openaiLogoRegular)
		case .web: DesktopIcons.image(.globe)
		case .attachment:
			DesktopIcons.image(.fileDocument)
		case .folder: DesktopIcons.image(.folder)
		}
	}

	private func agentRow(
		_ summary: NSButton,
		agents: [CodexSubagentActivity]
	) -> NSView
	{
		let avatars = ConversationSubagentAvatars.make(agents)
		let row = AppKitLayout.horizontalStack(
			[avatars, summary],
			spacing: Layout.agentRowSpacing
		)
		row.heightAnchor.constraint(equalToConstant: Layout.contentRowHeight).isActive = true
		summary.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		return row
	}

	private func header(_ name: String) -> NSView
	{
		let title = label(name)
		title.lineBreakMode = .byTruncatingTail
		title.maximumNumberOfLines = 1
		title.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		title.setAccessibilityLabel(name)
		title.toolTip = name
		return AppKitLayout.horizontalStack(
			[title, NSView(), unresolvedButton(
				"…",
				label: "Summary action unavailable"
			)],
			spacing: 8
		)
	}

	private func unresolvedButton(
		_ title: String,
		label: String
	) -> NSButton
	{
		let button = NSButton(
			title: title,
			target: nil,
			action: nil
		)
		button.isBordered = false
		button.isEnabled = false
		button.image = PinnedSummaryIcons.image(title == "+" ? .plus : .ellipsis)
		button.imagePosition = .imageOnly
		button.widthAnchor.constraint(equalToConstant: 18).isActive = true
		button.heightAnchor.constraint(equalToConstant: 18).isActive = true
		button.setAccessibilityLabel(label)
		button.toolTip = "Action unavailable: behavior has not been defined"
		return button
	}

	private func button(
		_ title: String,
		symbol: String?,
		destination: ContextPanelDestination,
		recordID: String? = nil
	) -> NSButton
	{
		let button = DesktopAttributedTitleButton(
			title: title,
			target: self,
			action: #selector(navigate(_:))
		)
		button.isBordered = false
		button.alignment = .left
		button.font = .systemFont(ofSize: 13)
		button.contentTintColor = .labelColor
		button.attributedTitle = attributedTitle(
			title,
			color: .labelColor
		)
		button.image = symbol.flatMap
		{
			NSImage(
				systemSymbolName: $0,
				accessibilityDescription: nil
			)
		}
		button.imagePosition = .imageLeading
		button.imageScaling = .scaleProportionallyDown
		button.cell?.lineBreakMode = .byTruncatingTail
		button.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		button.setAccessibilityLabel(title)
		button.toolTip = title
		if let request = presentation?.request(
			destination,
			recordID: recordID
		)
		{
			actions[button] = request
		}
		else
		{
			button.isEnabled = false
		}
		return button
	}

	private func label(
		_ text: String,
		color: NSColor = .secondaryLabelColor
	) -> NSTextField
	{
		let label = NSTextField(labelWithString: text)
		label.lineBreakMode = .byTruncatingTail
		label.maximumNumberOfLines = 1
		label.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		label.font = .systemFont(ofSize: 13)
		label.textColor = color
		return label
	}

	private func add(_ view: NSView)
	{
		stack.addArrangedSubview(view)
		view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
	}

	private func addSectionHeading(_ heading: NSView)
	{
		heading.heightAnchor.constraint(equalToConstant: 20).isActive = true
		add(heading)
	}

	private func iconButton(
		_ image: NSImage?,
		title: String,
		destination: ContextPanelDestination
	) -> NSButton
	{
		let icon = button(
			title,
			symbol: nil,
			destination: destination
		)
		icon.image = image
		icon.imagePosition = .imageOnly
		icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
		icon.heightAnchor.constraint(equalToConstant: 18).isActive = true
		return icon
	}

	private func makeScrollView() -> NSScrollView
	{
		let scrollView = NSScrollView()
		scrollView.drawsBackground = false
		scrollView.hasVerticalScroller = true
		scrollView.autohidesScrollers = true
		let document = PinnedSummaryDocumentView()
		document.translatesAutoresizingMaskIntoConstraints = false
		stack.translatesAutoresizingMaskIntoConstraints = false
		document.addSubview(stack)
		scrollView.documentView = document
		// Extra card height stays below the summary instead of stretching its rows.
		let preferredBottom = stack.bottomAnchor.constraint(equalTo: document.bottomAnchor)
		preferredBottom.priority = NSLayoutConstraint.Priority(1)
		NSLayoutConstraint.activate([
			document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
			document.heightAnchor
				.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
			stack.topAnchor.constraint(equalTo: document.topAnchor),
			stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
			stack.bottomAnchor.constraint(lessThanOrEqualTo: document.bottomAnchor),
			preferredBottom,
		])
		return scrollView
	}

	private func addDivider()
	{
		let divider = DesktopSurface(AppKitColorTokens.border)
		add(divider)
		divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
		stack.setCustomSpacing(
			8,
			after: divider
		)
	}

	private func attributedTitle(
		_ text: String,
		color: NSColor
	) -> NSAttributedString
	{
		NSAttributedString(
			string: text,
			attributes: [
				.font: NSFont.systemFont(ofSize: 13),
				.foregroundColor: color,
			]
		)
	}

	private func statusLabel(_ text: String) -> NSTextField
	{
		let status = label(text)
		status.font = .systemFont(ofSize: 11)
		status.toolTip = text
		status.setAccessibilityLabel(text)
		return status
	}

	@objc private func navigate(_ sender: NSButton)
	{
		guard let request = actions[sender], request.owner == presentation?.owner
		else
		{
			return
		}
		onNavigate?(request)
	}

	@objc private func toggleSources(_ sender: NSButton)
	{
		guard let presentation, sender === sourcesDisclosureButton
		else
		{
			return
		}
		sourcesExpanded.toggle()
		renderContent(presentation)
		onContentHeightChange?()
	}

}

private final class PinnedSummaryDocumentView: NSView
{
	override var isFlipped: Bool
	{
		true
	}
}
