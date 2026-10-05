import AppKit

/// Shows recorded conversation resources and activity without executing source content.
@MainActor
final class ConversationSourcesViewController: NSViewController
{
	let owner: FeaturePresentationOwner
	private(set) var sources: ConversationLocalSources
	var onOpen: ((ConversationLocalSources.Record) -> Bool)?
	private var rows: [String: NSView] = [:]
	private var buttons: [NSButton: ConversationLocalSources.Record] = [:]
	private var tasks: [Task<Void, Never>] = []
	private var renderGeneration = 0
	private var expandedInvocations = Set<String>()
	private var disclosures: [NSButton: (id: String, detail: NSView, stack: NSStackView)] = [:]
	private let status = NSTextField(wrappingLabelWithString: "")
	private let rawOutput = SourceRawOutputPresenter()

	init(
		owner: FeaturePresentationOwner,
		sources: ConversationLocalSources
	)
	{
		self.owner = owner
		self.sources = sources
		super.init(
			nibName: nil,
			bundle: nil
		)
	}

	required init?(coder: NSCoder)
	{
		return nil
	}

	override func loadView()
	{
		let scroll = NSScrollView()
		scroll.hasVerticalScroller = true
		scroll.autohidesScrollers = true
		scroll.drawsBackground = false
		view = scroll
		renderSources(in: scroll)
	}

	func update(_ sources: ConversationLocalSources)
	{
		guard self.sources.records != sources.records
		else
		{
			return
		}
		self.sources = sources
		guard isViewLoaded, let scroll = view as? NSScrollView
		else
		{
			return
		}
		let origin = scroll.contentView.bounds.origin
		let focusID = focusedIdentifier(in: scroll)
		renderSources(in: scroll)
		if let focusID, let focused = findView(
			identifier: focusID,
			in: scroll
		)
		{
			scroll.window?.makeFirstResponder(focused)
		}
		scroll.layoutSubtreeIfNeeded()
		let bounds = NSRect(
			origin: origin,
			size: scroll.contentView.bounds.size
		)
		scroll.contentView.scroll(to: scroll.contentView.constrainBoundsRect(bounds).origin)
		scroll.reflectScrolledClipView(scroll.contentView)
	}

	func invalidate()
	{
		rawOutput.dismiss()
		renderGeneration += 1
		for task in tasks
		{
			task.cancel()
		}
		tasks.removeAll()
	}

	private func focusedIdentifier(in root: NSView) -> NSUserInterfaceItemIdentifier?
	{
		guard let responder = root.window?.firstResponder
		else
		{
			return nil
		}
		if responder === root || (root as? NSTextField)?.currentEditor() === responder
		{
			return root.identifier
		}
		for child in root.subviews
		{
			if let identifier = focusedIdentifier(in: child)
			{
				return identifier
			}
		}
		return nil
	}

	private func findView(
		identifier: NSUserInterfaceItemIdentifier,
		in root: NSView
	) -> NSView?
	{
		if root.identifier == identifier
		{
			return root
		}
		for child in root.subviews
		{
			if let match = findView(
				identifier: identifier,
				in: child
			)
			{
				return match
			}
		}
		return nil
	}

	private func renderSources(in scroll: NSScrollView)
	{
		invalidate()
		rows.removeAll()
		buttons.removeAll()
		disclosures.removeAll()
		let stack = AppKitLayout.verticalStack(
			[],
			spacing: 0
		)
		if sources.records.isEmpty
		{
			let empty =
				NSTextField(wrappingLabelWithString: "No sources in loaded conversation history")
			empty.textColor = .secondaryLabelColor
			stack.addArrangedSubview(empty)
		}
		for record in sources.records
		{
			let row = record.kind == .tool || record.kind == .web
				? makeActivityRow(for: record) : makeRow(for: record)
			stack.addArrangedSubview(row)
			row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
			let divider = NSBox()
			divider.boxType = .separator
			stack.addArrangedSubview(divider)
			divider.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		status.textColor = .secondaryLabelColor
		status.font = .systemFont(ofSize: 12)
		status.isHidden = true
		stack.addArrangedSubview(status)
		status.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		let document = ConversationSourcesDocumentView()
		AppKitLayout.pin(
			stack,
			to: document,
			inset: 20
		)
		document.translatesAutoresizingMaskIntoConstraints = false
		scroll.documentView = document
		document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
	}

	private func makeRow(for record: ConversationLocalSources.Record) -> NSView
	{
		let image = NSImageView()
		image.image = resourceIcon(for: record)
		image.identifier = NSUserInterfaceItemIdentifier("source-icon:\(record.id)")
		image.toolTip = String(describing: record.kind)
		image.imageScaling = record
			.kind == .audio ? .scaleProportionallyDown : .scaleProportionallyUpOrDown
		image.setAccessibilityElement(false)
		let button = NSButton(
			title: record.name,
			target: self,
			action: #selector(openSource(_:))
		)
		button.isBordered = false
		button.alignment = .left
		button.font = .systemFont(
			ofSize: 14,
			weight: .medium
		)
		button.toolTip = record.displayPath
		button.cell?.lineBreakMode = .byTruncatingTail
		button.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		button.setAccessibilityLabel("Open source: \(record.name)")
		button.identifier = NSUserInterfaceItemIdentifier("source-open:\(record.id)")
		button.isEnabled = record.url
			.map
			{
				!$0.isFileURL || FileManager.default.isReadableFile(atPath: $0.path)
			} ?? false
		let path = NSTextField(wrappingLabelWithString: record.displayPath)
		path.textColor = .tertiaryLabelColor
		path.font = .systemFont(ofSize: 13)
		path.isSelectable = true
		path.identifier = NSUserInterfaceItemIdentifier("source-path:\(record.id)")
		path.toolTip = record.displayPath
		path.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		let provenance = NSTextField(labelWithString: record.association)
		provenance.textColor = .secondaryLabelColor
		provenance.font = .systemFont(ofSize: 13)
		provenance.lineBreakMode = .byTruncatingTail
		provenance.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		let state = NSTextField(wrappingLabelWithString: record
			.kind == .image ? "Image unavailable" : "Source unavailable")
		state.textColor = .secondaryLabelColor
		state.font = .systemFont(ofSize: 11)
		state.isHidden = button.isEnabled || record.isInlineImage
		let duration = NSTextField(labelWithString: "")
		duration.textColor = .secondaryLabelColor
		duration.font = .systemFont(ofSize: 13)
		duration.identifier = NSUserInterfaceItemIdentifier("source-duration:\(record.id)")
		duration.isHidden = true
		let labels = AppKitLayout.verticalStack(
			[button, path, duration, provenance, state],
			spacing: 4
		)
		labels.setCustomSpacing(
			14,
			after: path
		)
		let row = NSView()
		row.addSubview(image)
		row.addSubview(labels)
		image.translatesAutoresizingMaskIntoConstraints = false
		labels.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			image.leadingAnchor.constraint(equalTo: row.leadingAnchor),
			image.topAnchor.constraint(
				equalTo: row.topAnchor,
				constant: 17
			),
			image.widthAnchor.constraint(equalToConstant: 24),
			image.heightAnchor.constraint(equalToConstant: record.kind == .audio ? 18 : 24),
			labels.leadingAnchor.constraint(
				equalTo: image.trailingAnchor,
				constant: 12
			),
			labels.trailingAnchor.constraint(equalTo: row.trailingAnchor),
			labels.topAnchor.constraint(
				equalTo: row.topAnchor,
				constant: 14
			),
			labels.bottomAnchor.constraint(
				equalTo: row.bottomAnchor,
				constant: -20
			),
			button.widthAnchor.constraint(equalTo: labels.widthAnchor),
			path.widthAnchor.constraint(equalTo: labels.widthAnchor),
			duration.widthAnchor.constraint(equalTo: labels.widthAnchor),
			provenance.widthAnchor.constraint(equalTo: labels.widthAnchor),
			state.widthAnchor.constraint(equalTo: labels.widthAnchor),
		])
		rows[record.id] = row
		buttons[button] = record
		if record.kind == .audio, let sourcePath = record.url?.path, button.isEnabled
		{
			let generation = renderGeneration
			tasks.append(Task
			{
				[weak self, weak duration, weak labels, weak path] in
				guard let value = await SourceAudioMetadataLoader.duration(path: sourcePath),
						!Task.isCancelled, let self, self.renderGeneration == generation,
						let duration, let labels, let path
				else
				{
					return
				}
				duration.stringValue = "Duration: \(value)"
				duration.setAccessibilityLabel("Duration: \(value)")
				duration.isHidden = false
				labels.setCustomSpacing(
					4,
					after: path
				)
				labels.setCustomSpacing(
					14,
					after: duration
				)
			})
		}
		if record.kind == .image, record.isInlineImage || button.isEnabled
		{
			let sourcePath = record.isInlineImage ? record.path : (record.url?.path ?? record.path)
			let generation = renderGeneration
			tasks.append(Task
			{
				[weak self, weak image, weak state] in
				let data = await SourceThumbnailLoader.load(path: sourcePath)
				guard !Task.isCancelled, let self, self.renderGeneration == generation,
						self.sources.records.contains(record),
						let image, let state
				else
				{
					return
				}
				if let data, let preview = NSImage(data: data)
				{
					image.image = preview
				}
				else
				{
					state.stringValue = "Preview unavailable"
					state.isHidden = false
				}
			})
		}
		return row
	}

	private func resourceIcon(for record: ConversationLocalSources.Record) -> NSImage?
	{
		let icon: DesktopIcon
		switch record.kind
		{
		case .image: icon = .fileImage
		case .folder: icon = .folder
		case .audio: icon = .fileAudio
		case .pdf: icon = .fileDocument
		case .file: icon = .file
		case .page: icon = .document
		case .tool: icon = .tools
		case .web: icon = .globe
		}
		return DesktopIcons.image(
			icon,
			size: record.kind == .audio ? 18 : 24
		)
	}

	private func activityIcon(for record: ConversationLocalSources.Record) -> NSImage?
	{
		if record.kind == .web
		{
			return DesktopIcons.image(
				.globe,
				size: 16
			)
		}
		switch record.name
		{
		case "Space": return DesktopIcons.image(
				.stack,
				size: 16
			)
		case "ChatGPT App Tools": return DesktopIcons.image(
				.openaiLogoRegular,
				size: 16
			)
		case "Terminal": return DesktopIcons.image(
				.terminal,
				size: 16
			)
		default: return resourceIcon(for: record)
		}
	}

	private func operationTitle(
		_ operation: String,
		count: Int
	) -> String
	{
		switch operation
		{
		case "list_pages": return "Listed pages " + (count == 1 ? "once" : "\(count) times")
		case "list_spaces": return "Listed spaces " + (count == 1 ? "once" : "\(count) times")
		case "read_page": return "Read \(count) " + (count == 1 ? "page" : "pages")
		case "read_thread": return "Read chat " + (count == 1 ? "once" : "\(count) times")
		case "list_threads": return "Listed chats " + (count == 1 ? "once" : "\(count) times")
		case "list_artifacts", "list_attached_artifacts":
			return "Listed attached artifacts " + (count == 1 ? "once" : "\(count) times")
		case "Search": return "Searched \(count) " + (count == 1 ? "time" : "times")
		case "Open": return "Opened \(count) " + (count == 1 ? "page" : "pages")
		case "Find": return "Found text on \(count) " + (count == 1 ? "page" : "pages")
		case "Command": return "Ran \(count) " + (count == 1 ? "command" : "commands")
		case "": return "Activity details"
		default: return operation.replacingOccurrences(
				of: "_",
				with: " "
			)
				+ (count == 1 ? " once" : " \(count) times")
		}
	}

	private func makeActivityRow(for record: ConversationLocalSources.Record) -> NSView
	{
		let title = NSTextField(labelWithString: record.name)
		title.font = .systemFont(ofSize: 13)
		title.textColor = SourceResultCodeCard.activityTitleColor
		title.lineBreakMode = .byTruncatingTail
		title.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		let content = AppKitLayout.verticalStack(
			[title],
			spacing: 8
		)
		content.setCustomSpacing(
			18,
			after: title
		)
		var groups: [(operation: String, invocations: [ConversationLocalSources.Invocation])] = []
		for invocation in record.invocations
		{
			if let index = groups.firstIndex(where:
				{
					$0.operation == invocation.operation
				})
			{
				groups[index].invocations.append(invocation)
			}
			else
			{
				groups.append((invocation.operation, [invocation]))
			}
		}
		let canonicalOrder = record.kind == .web
			? ["Search", "Open", "Find", "Other"]
			: [
				"read_thread",
				"list_threads",
				"list_pages",
				"list_spaces",
				"read_page",
				"list_artifacts",
				"list_attached_artifacts"
			]
		groups = groups.enumerated().sorted
		{
			lhs, rhs in
			let left = canonicalOrder.firstIndex(of: lhs.element.operation) ?? canonicalOrder.count
			let right = canonicalOrder.firstIndex(of: rhs.element.operation) ?? canonicalOrder.count
			return left == right ? lhs.offset < rhs.offset : left < right
		}.map
		{
			$0.element
		}
		if groups.isEmpty, !record.association.isEmpty
		{
			let association = NSTextField(wrappingLabelWithString: record.association)
			association.textColor = .secondaryLabelColor
			association.font = .systemFont(ofSize: 13)
			content.addArrangedSubview(association)
		}
		for group in groups
		{
			let id = "\(record.id):operation:\(group.operation)"
			let label = operationTitle(
				group.operation,
				count: group.invocations.count
			)
			let disclosure = SourceOperationDisclosureButton(
				title: label,
				target: self,
				action: #selector(toggleInvocation(_:))
			)
			disclosure.setButtonType(.pushOnPushOff)
			disclosure.isBordered = false
			disclosure.imagePosition = .noImage
			if let cell = disclosure.cell as? NSButtonCell
			{
				cell.highlightsBy = []
				cell.showsStateBy = []
			}
			disclosure.alignment = .left
			disclosure.font = .systemFont(ofSize: 13)
			disclosure.contentTintColor = SourceResultCodeCard.activityLabelColor
			disclosure.state = expandedInvocations.contains(id) ? .on : .off
			let plainTitle = NSAttributedString(
				string: label,
				attributes: [
					.font: NSFont.systemFont(ofSize: 13),
					.foregroundColor: SourceResultCodeCard.activityLabelColor,
				]
			)
			disclosure.attributedTitle = plainTitle
			disclosure.attributedAlternateTitle = plainTitle
			disclosure.setAccessibilityValue(disclosure.state == .on ? "Expanded" : "Collapsed")
			disclosure.identifier = NSUserInterfaceItemIdentifier("source-disclosure:\(id)")
			disclosure.setAccessibilityLabel(label)
			disclosure.cell?.lineBreakMode = .byTruncatingTail
			disclosure.setContentCompressionResistancePriority(
				.defaultLow,
				for: .horizontal
			)
			let detail = AppKitLayout.verticalStack(
				[],
				// Each output already includes a 4pt gap and a 24pt raw-action row.
				spacing: 6
			)
			detail.identifier = NSUserInterfaceItemIdentifier("source-detail:\(id)")
			let orderedInvocations = group.invocations.enumerated().sorted
			{
				lhs, rhs in
				if lhs.element.isError == rhs.element.isError
				{
					return lhs.offset < rhs.offset
				}
				return !lhs.element.isError
			}.map
			{
				$0.element
			}
			for invocation in orderedInvocations
			{
				let payload = invocation.resultText.isEmpty
					? "No result recorded." +
					(invocation.status.isEmpty ? "" : "\nStatus: \(invocation.status)")
					: invocation.resultText
				let card = SourceResultCodeCard(
					text: payload,
					language: invocation.resultLanguage,
					identifier: "source-result:\(record.id):\(invocation.id)",
					isError: invocation.isError
				)
				let output = SourceRawOutputEntryView(card: card, id: invocation.id)
				{ [weak self] in
					guard let self, self.sources.records.contains(record),
						let window = self.view.window
					else { return }
					self.rawOutput.present(invocation, in: window)
				}
				detail.addArrangedSubview(output)
				output.widthAnchor.constraint(equalTo: detail.widthAnchor).isActive = true
			}
			detail.isHidden = disclosure.state == .off
			disclosure.updateDisclosureIndicator()

			content.addArrangedSubview(disclosure)
			content.addArrangedSubview(detail)
			content.setCustomSpacing(
				disclosure.state == .on ? 14 : 8,
				after: disclosure
			)
			disclosures[disclosure] = (id, detail, content)
		}
		for child in content.arrangedSubviews
		{
			if child is NSButton
			{
				child.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor).isActive = true
				child.setContentHuggingPriority(
					.defaultHigh,
					for: .horizontal
				)
			}
			else
			{
				child.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
			}
		}
		let image = NSImageView()
		image.image = activityIcon(for: record)
		image.imageScaling = .scaleProportionallyDown
		image.contentTintColor = SourceResultCodeCard.activityTitleColor
		image.setAccessibilityElement(false)
		image.identifier = NSUserInterfaceItemIdentifier("source-icon:\(record.id)")
		let row = NSView()
		row.addSubview(image)
		row.addSubview(content)
		image.translatesAutoresizingMaskIntoConstraints = false
		content.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			image.leadingAnchor.constraint(equalTo: row.leadingAnchor),
			image.topAnchor.constraint(
				equalTo: row.topAnchor,
				constant: 14
			),
			image.widthAnchor.constraint(equalToConstant: 16),
			image.heightAnchor.constraint(equalToConstant: 16),
			content.leadingAnchor.constraint(
				equalTo: image.trailingAnchor,
				constant: 8
			),
			content.trailingAnchor.constraint(equalTo: row.trailingAnchor),
			content.topAnchor.constraint(
				equalTo: row.topAnchor,
				constant: 14
			),
			content.bottomAnchor.constraint(
				equalTo: row.bottomAnchor,
				constant: -20
			),
		])
		rows[record.id] = row
		return row
	}

	@objc private func toggleInvocation(_ sender: NSButton)
	{
		guard let disclosure = disclosures[sender]
		else
		{
			return
		}
		if sender.state == .on
		{
			expandedInvocations.insert(disclosure.id)
		}
		else
		{
			expandedInvocations.remove(disclosure.id)
		}
		disclosure.detail.isHidden = sender.state == .off
		disclosure.stack.setCustomSpacing(
			sender.state == .on ? 14 : 8,
			after: sender
		)
		(sender as? SourceOperationDisclosureButton)?.updateDisclosureIndicator()
		sender.setAccessibilityValue(sender.state == .on ? "Expanded" : "Collapsed")
	}

	func select(_ request: ContextPanelRequest)
	{
		guard let record = sources.record(
			for: request,
			owner: owner
		)
		else
		{
			return
		}
		_ = view
		if let row = rows[record.id]
		{
			row.scrollToVisible(row.bounds)
		}
	}

	func waitForPreviews() async
	{
		for task in tasks
		{
			await task.value
		}
	}

	@objc private func openSource(_ sender: NSButton)
	{
		guard let record = buttons[sender]
		else
		{
			return
		}
		if onOpen?(record) != true
		{
			status.isHidden = false
			status.stringValue = "Unable to open \(record.name). "
				+ "The source may no longer be available."
		}
	}
}

private final class ConversationSourcesDocumentView: NSView
{
	override var isFlipped: Bool
	{
		true
	}
}

/// Reserves the trailing icon slot so hover changes do not move the operation label.
@MainActor
private final class SourceOperationDisclosureButton: NSButton
{
	private enum Indicator: Equatable
	{
		case hidden, hovered, expanded
	}
	private var displayedIndicator: Indicator?
	private var disclosureTrackingArea: NSTrackingArea?
	private var isHovered = false
	private let reservedIcon = NSImage(size: NSSize(
		width: 16,
		height: 16
	))

	func updateDisclosureIndicator()
	{
		let indicator: Indicator = state == .on ? .expanded : (isHovered ? .hovered : .hidden)
		guard displayedIndicator != indicator
		else
		{
			return
		}
		displayedIndicator = indicator
		imagePosition = .imageTrailing
		switch indicator
		{
		case .expanded: image = DesktopIcons.image(.chevronDown)
		case .hovered: image = DesktopIcons.image(.chevronRight)
		case .hidden: image = reservedIcon
		}
	}

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		if let disclosureTrackingArea
		{
			removeTrackingArea(disclosureTrackingArea)
		}
		let area = NSTrackingArea(
			rect: .zero,
			options: [
				.mouseEnteredAndExited,
				.activeInKeyWindow,
				.inVisibleRect
			],
			owner: self,
			userInfo: nil
		)
		addTrackingArea(area)
		disclosureTrackingArea = area
		if let window, window.isKeyWindow
		{
			let point = convert(
				window.mouseLocationOutsideOfEventStream,
				from: nil
			)
			isHovered = !isHidden && visibleRect.contains(point)
		}
		else
		{
			isHovered = false
		}
		updateDisclosureIndicator()
	}

	override func mouseEntered(with event: NSEvent)
	{
		super.mouseEntered(with: event)
		isHovered = true
		updateDisclosureIndicator()
	}

	override func mouseExited(with event: NSEvent)
	{
		super.mouseExited(with: event)
		isHovered = false
		updateDisclosureIndicator()
	}

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		isHovered = false
		updateDisclosureIndicator()
	}
}
