import AppKit

@MainActor
final class PinnedSummaryViewController: NSViewController
{
	var onNavigate: ((ContextPanelRequest) -> Void)?
	private var presentation: PinnedSummaryPresentation?
	private let stack = NSStackView()
	private var thumbnailTasks: [Task<Void, Never>] = []
	private var actions: [NSButton: ContextPanelRequest] = [:]

	override func loadView()
	{
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = 6
		view = AppKitLayout.scrollableContent(
			stack,
			inset: 4
		)
		(view as? NSScrollView)?.drawsBackground = false
	}

	func render(_ presentation: PinnedSummaryPresentation)
	{
		guard self.presentation != presentation
		else
		{
			return
		}
		self.presentation = presentation
		_ = view
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
		add(header(presentation.contextName))
		addChanges(presentation)
		addDivider()
		addAgents(presentation)
		addSources(presentation)
	}

	private func addChanges(_ presentation: PinnedSummaryPresentation)
	{
		let changes = button(
			"Changes",
			symbol: nil,
			destination: .changes
		)
		changes.image = PinnedSummaryIcons.image(.changes)
		changes.contentTintColor = .labelColor
		// Borderless image buttons otherwise compress their title away inside a stack row.
		let readableWidth = ceil(changes.attributedTitle.size().width) + 24
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
			[changes, spacer],
			spacing: 8
		)
		if let totals = presentation.sections.changes.value
		{
			let additions = label(
				"+\(totals.additions)",
				color: .systemGreen
			)
			additions.setAccessibilityLabel("\(totals.additions) additions")
			let deletions = label(
				"−\(totals.deletions)",
				color: .systemRed
			)
			deletions.setAccessibilityLabel("\(totals.deletions) deletions")
			row.addArrangedSubview(additions)
			row.addArrangedSubview(deletions)
		}
		add(row)
		if let scope = presentation.sections.changesContext
		{
			add(statusLabel(scope))
		}
		if let message = presentation.sections.changes.message
		{
			add(statusLabel(message))
		}
	}

	private func addAgents(_ presentation: PinnedSummaryPresentation)
	{
		let section = presentation.sections.agents
		// Unavailable optional data is hidden; never turn an absent provider into a zero count.
		if case .unavailable = section
		{
			return
		}
		add(label("Subagents"))
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
			add(agentRow(summary))
		}
		if let message = section.message
		{
			add(statusLabel(message))
		}
		addDivider()
	}

	private func addSources(_ presentation: PinnedSummaryPresentation)
	{
		let sources = button(
			"Sources",
			symbol: nil,
			destination: .sources
		)
		sources.attributedTitle = attributedTitle(
			"Sources",
			color: .secondaryLabelColor
		)
		let plus = unresolvedButton(
			"+",
			label: "Sources action unavailable"
		)
		add(AppKitLayout.horizontalStack(
			[sources, NSView(), plus],
			spacing: 8
		))
		for source in presentation.sourcePreviews
		{
			add(sourceRow(
				source,
				presentation: presentation
			))
		}
		if presentation.sections.sources.value?.isEmpty == true
		{
			add(label("No sources"))
		}
		if let message = presentation.sections.sources.message
		{
			add(statusLabel(message))
		}
		let all = button(
			"View all",
			symbol: nil,
			destination: .sources
		)
		all.image = PinnedSummaryIcons.image(.viewAll)
		all.contentTintColor = .tertiaryLabelColor
		all.attributedTitle = attributedTitle(
			"View all",
			color: .tertiaryLabelColor
		)
		add(all)
	}

	private func sourceRow(
		_ source: PinnedSummaryPresentation.SourcePreview,
		presentation: PinnedSummaryPresentation
	) -> NSView
	{
		let imageView = NSImageView()
		let size: CGFloat = source.kind == .attachment ? 20 : 16
		imageView.image = sourceImage(for: source)
		imageView.contentTintColor = .secondaryLabelColor
		imageView.imageScaling = .scaleProportionallyUpOrDown
		imageView.setAccessibilityElement(false)
		imageView.widthAnchor.constraint(equalToConstant: size).isActive = true
		imageView.heightAnchor.constraint(equalToConstant: size).isActive = true

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
			spacing: 12
		)
		text.widthAnchor.constraint(
			equalTo: row.widthAnchor,
			constant: -size - 12
		).isActive = true
		row.heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
		if let path = source.thumbnailPath
		{
			let owner = presentation.owner
			thumbnailTasks.append(Task
			{
				[weak self, weak imageView] in
				let data = await SourceThumbnailLoader.load(path: path)
				guard !Task.isCancelled, self?.presentation?.owner == owner,
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
		switch source.kind
		{
		case .tool: PinnedSummaryIcons.image(.appTools)
		case .web: PinnedSummaryIcons.image(.webSearch)
		case .attachment:
			GitReviewReferenceIcons.fileImage(
				relativePath: source.label,
				size: 20
			)
		case .folder: DesktopIcons.image(.folder)
		}
	}

	private func agentRow(_ summary: NSButton) -> NSView
	{
		var views: [NSView] = PinnedSummaryIcons.agentImages().map
		{
			artwork in
			let image = NSImageView()
			image.image = artwork
			image.setAccessibilityElement(false)
			image.widthAnchor.constraint(equalToConstant: 16).isActive = true
			image.heightAnchor.constraint(equalToConstant: 16).isActive = true
			return image
		}
		views.append(summary)
		let row = AppKitLayout.horizontalStack(
			views,
			spacing: 4
		)
		// Reserve the four fixed glyph widths and four gaps; the status uses the remainder.
		let artworkWidth = CGFloat(views.count - 1) * (16 + 4)
		summary.widthAnchor.constraint(
			equalTo: row.widthAnchor,
			constant: -artworkWidth
		).isActive = true
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
		let button = NSButton(
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

	private func addDivider()
	{
		let divider = DesktopSurface(DesktopTheme.border)
		add(divider)
		divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
		stack.setCustomSpacing(
			10,
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
}
