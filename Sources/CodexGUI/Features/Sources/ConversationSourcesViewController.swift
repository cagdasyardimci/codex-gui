import AppKit

/// Shows recorded conversation resources and activity without executing source content.
@MainActor
final class ConversationSourcesViewController: NSViewController
{
	let owner: FeaturePresentationOwner
	private(set) var sources: ConversationLocalSources
	var onOpen: ((ConversationLocalSources.Record) -> Bool)?
	private var rows: [String: NSView] = [:]
	private var renderedRecords: [String: ConversationLocalSources.Record] = [:]
	private var dividers: [String: NSBox] = [:]
	private var buttons: [NSButton: ConversationLocalSources.Record] = [:]
	private let previews: SourcePreviewCoordinator
	private var needsSourceRender = true
	private var isInvalidated = false
	private var expandedInvocations = Set<String>()
	private var disclosures: [NSButton: Disclosure] = [:]
	private var results: [InvocationKey: CachedResult] = [:]
	private let sourceStack = AppKitLayout.verticalStack(
		[],
		spacing: 0
	)
	private let status = DesktopStatusView(
		message: "",
		presentation: .inline
	)
	private let rawOutput = SourceRawOutputPresenter()

	private struct InvocationKey: Hashable
	{
		let recordID: String
		let invocationID: String
	}

	private struct CachedResult
	{
		let invocation: ConversationLocalSources.Invocation
		let output: SourceRawOutputEntryView
		var widthConstraint: NSLayoutConstraint? = nil
	}

	private struct OperationGroup
	{
		let operation: String
		var invocations: [ConversationLocalSources.Invocation]
	}

	private struct Disclosure
	{
		let id: String
		let recordID: String
		let invocations: [ConversationLocalSources.Invocation]
		let detail: NSStackView
		let stack: NSStackView
	}

	init(
		owner: FeaturePresentationOwner,
		sources: ConversationLocalSources,
		loadThumbnail: @escaping @Sendable (String) async -> Data? = SourceThumbnailLoader
			.load(path:)
	)
	{
		self.owner = owner
		self.sources = sources
		previews = SourcePreviewCoordinator(
			records: sources.records,
			loadThumbnail: loadThumbnail
		)
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
		let scroll = ConversationSourcesScrollView()
		scroll.hasVerticalScroller = true
		scroll.autohidesScrollers = true
		scroll.drawsBackground = false
		view = scroll
		let document = ConversationSourcesDocumentView()
		AppKitLayout.pin(
			sourceStack,
			to: document,
			inset: 20
		)
		document.translatesAutoresizingMaskIntoConstraints = false
		scroll.documentView = document
		document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
		sourceStack.addArrangedSubview(status)
		status.widthAnchor.constraint(equalTo: sourceStack.widthAnchor).isActive = true
		scroll.onReveal =
		{
			[weak self] in
			self?.renderPendingSources()
		}
		renderPendingSources()
	}

	func update(_ sources: ConversationLocalSources)
	{
		guard !isInvalidated, self.sources.records != sources.records
		else
		{
			return
		}
		self.sources = sources
		rawOutput.update(records: sources.records)
		needsSourceRender = true
		previews.update(
			records: sources.records,
			renderedRecords: renderedRecords
		)
		renderPendingSources()
	}

	private func renderPendingSources(force: Bool = false)
	{
		guard !isInvalidated, needsSourceRender, isViewLoaded,
				let scroll = view as? NSScrollView,
				force || !scroll.isHiddenOrHasHiddenAncestor
		else
		{
			return
		}
		needsSourceRender = false
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
		isInvalidated = true
		rawOutput.dismiss()
		previews.invalidate()
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
		let current = Dictionary(
			sources.records.map
			{
				($0.id, $0)
			},
			uniquingKeysWith:
			{
				_, latest in latest
			}
		)
		let changed = Set(renderedRecords.keys.filter
		{
			renderedRecords[$0] != current[$0]
		}).union(previews.takeInterruptedRecords())
		retainCurrentResults(
			current,
			changedRecords: changed
		)
		for id in changed
		{
			rows.removeValue(forKey: id)
			dividers.removeValue(forKey: id)
			renderedRecords.removeValue(forKey: id)
		}
		buttons = buttons.filter
		{
			!changed.contains($0.value.id)
		}
		disclosures = disclosures.filter
		{
			!changed.contains($0.value.recordID)
		}
		let currentGroups = Set(sources.records.flatMap
		{
			record in
			record.invocations.map
			{
				"\(record.id):operation:\($0.operation)"
			}
		})
		expandedInvocations.formIntersection(currentGroups)
		let retainedViews = Set(rows.values.map(ObjectIdentifier.init)
			+ dividers.values.map(ObjectIdentifier.init) + [ObjectIdentifier(status)])
		for child in sourceStack.arrangedSubviews
			where !retainedViews.contains(ObjectIdentifier(child))
		{
			sourceStack.removeArrangedSubview(child)
			child.removeFromSuperview()
		}
		var insertionIndex = 0
		if sources.records.isEmpty
		{
			let empty = DesktopStatusView(
				message: "No sources in loaded conversation history",
				presentation: .conversation
			)
			sourceStack.insertArrangedSubview(
				empty,
				at: insertionIndex
			)
			insertionIndex += 1
		}
		for record in sources.records
		{
			let row: NSView
			let divider: NSBox
			let isNewRow: Bool
			if let existing = rows[record.id], let existingDivider = dividers[record.id]
			{
				row = existing
				divider = existingDivider
				isNewRow = false
			}
			else
			{
				row = record.kind == .tool || record.kind == .web
					? makeActivityRow(for: record) : makeRow(for: record)
				divider = NSBox()
				divider.boxType = .separator
				dividers[record.id] = divider
				renderedRecords[record.id] = record
				isNewRow = true
			}
			// Moving arranged positions keeps retained views and their constraints installed.
			sourceStack.insertArrangedSubview(
				row,
				at: insertionIndex
			)
			sourceStack.insertArrangedSubview(
				divider,
				at: insertionIndex + 1
			)
			insertionIndex += 2
			if isNewRow
			{
				row.widthAnchor.constraint(equalTo: sourceStack.widthAnchor).isActive = true
				divider.widthAnchor.constraint(equalTo: sourceStack.widthAnchor).isActive = true
			}
		}
		status.setMessage("")
		sourceStack.insertArrangedSubview(
			status,
			at: insertionIndex
		)
	}

	private func retainCurrentResults(
		_ records: [String: ConversationLocalSources.Record],
		changedRecords: Set<String>
	)
	{
		var invocations: [InvocationKey: ConversationLocalSources.Invocation] = [:]
		for record in records.values
		{
			for invocation in record.invocations
			{
				let key = InvocationKey(
					recordID: record.id,
					invocationID: invocation.id
				)
				invocations[key] = invocation
			}
		}
		for key in Array(results.keys)
		{
			guard var cached = results[key]
			else
			{
				continue
			}
			let current = invocations[key]
			if current != cached.invocation || changedRecords.contains(key.recordID)
			{
				cached.widthConstraint?.isActive = false
				cached.widthConstraint = nil
				(cached.output.superview as? NSStackView)?.removeArrangedSubview(cached.output)
				cached.output.removeFromSuperview()
			}
			results[key] = current == cached.invocation ? cached : nil
		}
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
		let state = DesktopStatusView(
			message: record.kind == .image ? "Image unavailable" : "Source unavailable",
			presentation: .inlineCompact
		)
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
			previews.loadAudio(
				for: record,
				path: sourcePath
			)
			{
				[weak duration, weak labels, weak path] value in
				guard let duration, let labels, let path
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
			}
		}
		if record.kind == .image, record.isInlineImage || button.isEnabled
		{
			let sourcePath = record.isInlineImage ? record.path : (record.url?.path ?? record.path)
			previews.loadImage(
				for: record,
				path: sourcePath
			)
			{
				[weak image, weak state] data in
				guard let image, let state
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
			}
		}
		return row
	}

	private func resourceIcon(for record: ConversationLocalSources.Record) -> NSImage?
	{
		DesktopIcons.image(
			record.kind == .tool ? .tools : record.iconIdentifier,
			size: record.kind == .audio ? 18 : 24
		)
	}

	private func activityIcon(for record: ConversationLocalSources.Record) -> NSImage?
	{
		guard record.kind == .web || (record.kind == .tool && record.iconIdentifier != .tools)
		else
		{
			return resourceIcon(for: record)
		}
		return DesktopIcons.image(
			record.iconIdentifier,
			size: 16
		)
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

		let groups = orderedOperationGroups(for: record)
		if groups.isEmpty, !record.association.isEmpty
		{
			let association = NSTextField(wrappingLabelWithString: record.association)
			association.textColor = .secondaryLabelColor
			association.font = .systemFont(ofSize: 13)
			content.addArrangedSubview(association)
		}
		for group in groups
		{
			appendActivityOperation(
				group,
				recordID: record.id,
				to: content
			)
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

	private func orderedOperationGroups(
		for record: ConversationLocalSources.Record
	) -> [OperationGroup]
	{
		var groups: [OperationGroup] = []
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
				groups.append(OperationGroup(
					operation: invocation.operation,
					invocations: [invocation]
				))
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
		return groups.enumerated().sorted
		{
			lhs, rhs in
			let left = canonicalOrder.firstIndex(of: lhs.element.operation) ?? canonicalOrder.count
			let right = canonicalOrder.firstIndex(of: rhs.element.operation) ?? canonicalOrder.count
			return left == right ? lhs.offset < rhs.offset : left < right
		}.map
		{
			$0.element
		}
	}

	private func appendActivityOperation(
		_ group: OperationGroup,
		recordID: String,
		to content: NSStackView
	)
	{
		let id = "\(recordID):operation:\(group.operation)"
		let label = operationTitle(
			group.operation,
			count: group.invocations.count
		)
		let disclosure = DesktopDisclosureButton(
			title: label,
			expanded: expandedInvocations.contains(id),
			presentation: .hoverReveal,
			target: self,
			action: #selector(toggleInvocation(_:))
		)
		disclosure.setButtonType(.pushOnPushOff)
		disclosure.identifier = NSUserInterfaceItemIdentifier("source-disclosure:\(id)")
		disclosure.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		let detail = AppKitLayout.verticalStack(
			[],
			// Each output includes its own action row and content spacing.
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
		let groupDisclosure = Disclosure(
			id: id,
			recordID: recordID,
			invocations: orderedInvocations,
			detail: detail,
			stack: content
		)
		if disclosure.state == .on
		{
			populateResults(for: groupDisclosure)
		}
		detail.isHidden = disclosure.state == .off

		content.addArrangedSubview(disclosure)
		content.addArrangedSubview(detail)
		content.setCustomSpacing(
			disclosure.state == .on ? 14 : 8,
			after: disclosure
		)
		disclosures[disclosure] = groupDisclosure
	}

	private func populateResults(for disclosure: Disclosure)
	{
		guard disclosure.detail.arrangedSubviews.isEmpty
		else
		{
			return
		}
		for invocation in disclosure.invocations
		{
			let key = InvocationKey(
				recordID: disclosure.recordID,
				invocationID: invocation.id
			)
			var cached: CachedResult
			if let existing = results[key], existing.invocation == invocation
			{
				cached = existing
			}
			else
			{
				let payload = invocation.resultText.isEmpty
					? "No result recorded." +
					(invocation.status.isEmpty ? "" : "\nStatus: \(invocation.status)")
					: invocation.resultText
				let card = SourceResultCodeCard(
					text: payload,
					language: invocation.resultLanguage,
					identifier: "source-result:\(disclosure.recordID):\(invocation.id)",
					isError: invocation.isError
				)
				let output = SourceRawOutputEntryView(
					card: card,
					id: invocation.id
				)
				{
					[weak self] in
					guard let self, !self.isInvalidated,
							let record = self.sources.records.first(where:
							{
								$0.id == key.recordID
							}),
							record.invocations.contains(invocation), let window = self.view.window
					else
					{
						return
					}
					self.rawOutput.present(
						invocation,
						recordID: key.recordID,
						in: window
					)
				}
				cached = CachedResult(
					invocation: invocation,
					output: output
				)
			}
			cached.widthConstraint?.isActive = false
			disclosure.detail.addArrangedSubview(cached.output)
			let width = cached.output.widthAnchor.constraint(equalTo: disclosure.detail.widthAnchor)
			width.isActive = true
			cached.widthConstraint = width
			results[key] = cached
		}
	}

	@objc private func toggleInvocation(_ sender: NSButton)
	{
		guard !isInvalidated, let disclosure = disclosures[sender]
		else
		{
			return
		}
		if sender.state == .on
		{
			expandedInvocations.insert(disclosure.id)
			populateResults(for: disclosure)
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
		(sender as? DesktopDisclosureButton)?.setExpanded(sender.state == .on)
	}

	func select(_ request: ContextPanelRequest)
	{
		guard !isInvalidated, request.owner == owner, request.destination == .sources
		else
		{
			return
		}
		prepareForDisplay()
		guard let record = sources.record(
			for: request,
			owner: owner
		)
		else
		{
			return
		}
		if let row = rows[record.id]
		{
			row.scrollToVisible(row.bounds)
		}
	}

	/// Window containers call this before revealing a retained Sources view.
	func prepareForDisplay()
	{
		guard !isInvalidated
		else
		{
			return
		}
		_ = view
		renderPendingSources(force: true)
	}

	/// Captures registered previews so callers can join them after cancellation retires them.
	func previewTasks() -> [Task<Void, Never>]
	{
		previews.tasks()
	}

	func waitForPreviews() async
	{
		for task in previewTasks()
		{
			await task.value
		}
	}

	@objc private func openSource(_ sender: NSButton)
	{
		guard !isInvalidated, let record = buttons[sender], sources.records.contains(record)
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

/// Reveal hooks reconcile deferred updates before a retained Sources tab is shown again.
@MainActor
private final class ConversationSourcesScrollView: NSScrollView
{
	var onReveal: (() -> Void)?

	override func viewDidUnhide()
	{
		super.viewDidUnhide()
		onReveal?()
	}

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		onReveal?()
	}

	override func layout()
	{
		super.layout()
		onReveal?()
	}
}

private final class ConversationSourcesDocumentView: DesktopFlippedView
{
}
