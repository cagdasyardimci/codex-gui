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
	private var tasks: [String: Task<Void, Never>] = [:]
	private var interruptedPreviews = Set<String>()
	private var renderGeneration = 0
	private var needsSourceRender = true
	private var isInvalidated = false
	private var expandedInvocations = Set<String>()
	private var disclosures: [NSButton: Disclosure] = [:]
	private var results: [InvocationKey: CachedResult] = [:]
	private let sourceStack = AppKitLayout.verticalStack(
		[],
		spacing: 0
	)
	private let status = NSTextField(wrappingLabelWithString: "")
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
		needsSourceRender = true
		cancelObsoletePreviewTasks()
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
		renderGeneration += 1
		for task in tasks.values
		{
			task.cancel()
		}
		tasks.removeAll()
	}

	private func cancelObsoletePreviewTasks()
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
		for id in Array(tasks.keys) where renderedRecords[id] != current[id]
		{
			tasks.removeValue(forKey: id)?.cancel()
			interruptedPreviews.insert(id)
		}
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
		rawOutput.dismiss()
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
		}).union(interruptedPreviews)
		interruptedPreviews.removeAll()
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
			let empty =
				NSTextField(wrappingLabelWithString: "No sources in loaded conversation history")
			empty.textColor = .secondaryLabelColor
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
		status.textColor = .secondaryLabelColor
		status.font = .systemFont(ofSize: 12)
		status.isHidden = true
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
			tasks[record.id] = Task
			{
				[weak self, weak duration, weak labels, weak path] in
				guard let value = await SourceAudioMetadataLoader.duration(path: sourcePath),
						!Task.isCancelled, let self, self.renderGeneration == generation,
						self.sources.records.contains(record),
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
			}
		}
		if record.kind == .image, record.isInlineImage || button.isEnabled
		{
			let sourcePath = record.isInlineImage ? record.path : (record.url?.path ?? record.path)
			let generation = renderGeneration
			tasks[record.id] = Task
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
		disclosure.font = .systemFont(ofSize: 14)
		disclosure.contentTintColor = SourceResultCodeCard.activityLabelColor
		disclosure.state = expandedInvocations.contains(id) ? .on : .off
		let plainTitle = NSAttributedString(
			string: label,
			attributes: [
				.font: NSFont.systemFont(ofSize: 14),
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
		disclosure.updateDisclosureIndicator()

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
		(sender as? SourceOperationDisclosureButton)?.updateDisclosureIndicator()
		sender.setAccessibilityValue(sender.state == .on ? "Expanded" : "Collapsed")
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

	func waitForPreviews() async
	{
		for task in tasks.values
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

private final class ConversationSourcesDocumentView: NSView
{
	override var isFlipped: Bool
	{
		true
	}
}

/// Reserves the trailing icon slot so hover changes do not move the operation label.
@MainActor
private final class SourceOperationDisclosureButton: DesktopAttributedTitleButton
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
