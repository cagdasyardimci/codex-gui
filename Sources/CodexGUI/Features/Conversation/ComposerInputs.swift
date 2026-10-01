import AppKit

/// Keeps the add menu and model controls on one row when the pane has room.
@MainActor
final class ComposerToolbarView: NSView
{
	private var wideConstraints: [NSLayoutConstraint] = []
	private var compactConstraints: [NSLayoutConstraint] = []
	private var isCompact = false

	init(
		leadingControls: NSView,
		preferenceControl: NSView,
		actionControls: NSView
	)
	{
		super.init(frame: .zero)

		for controls in [leadingControls, preferenceControl, actionControls]
		{
			controls.translatesAutoresizingMaskIntoConstraints = false
			addSubview(controls)
		}

		wideConstraints = [
			leadingControls.leadingAnchor.constraint(equalTo: leadingAnchor),
			leadingControls.centerYAnchor.constraint(equalTo: centerYAnchor),
			leadingControls.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
			leadingControls.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
			preferenceControl.leadingAnchor.constraint(
				greaterThanOrEqualTo: leadingControls.trailingAnchor,
				constant: 12
			),
			preferenceControl.trailingAnchor.constraint(
				equalTo: actionControls.leadingAnchor,
				constant: -16
			),
			preferenceControl.centerYAnchor.constraint(equalTo: centerYAnchor),
			preferenceControl.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
			preferenceControl.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
			actionControls.trailingAnchor.constraint(equalTo: trailingAnchor),
			actionControls.topAnchor.constraint(equalTo: topAnchor),
			actionControls.bottomAnchor.constraint(equalTo: bottomAnchor),
		]
		compactConstraints = [
			leadingControls.leadingAnchor.constraint(equalTo: leadingAnchor),
			leadingControls.topAnchor.constraint(equalTo: topAnchor),
			preferenceControl.leadingAnchor.constraint(equalTo: leadingAnchor),
			preferenceControl.trailingAnchor.constraint(
				lessThanOrEqualTo: actionControls.leadingAnchor,
				constant: -16
			),
			preferenceControl.centerYAnchor.constraint(equalTo: actionControls.centerYAnchor),
			preferenceControl.topAnchor.constraint(
				greaterThanOrEqualTo: leadingControls.bottomAnchor,
				constant: 4
			),
			preferenceControl.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
			actionControls.topAnchor.constraint(
				equalTo: leadingControls.bottomAnchor,
				constant: 4
			),
			actionControls.trailingAnchor.constraint(equalTo: trailingAnchor),
			actionControls.bottomAnchor.constraint(equalTo: bottomAnchor),
		]

		NSLayoutConstraint.activate(wideConstraints)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func layout()
	{
		let shouldUseCompactLayout = bounds.width < 440
		if shouldUseCompactLayout != isCompact
		{
			NSLayoutConstraint.deactivate(isCompact ? compactConstraints : wideConstraints)
			isCompact = shouldUseCompactLayout
			NSLayoutConstraint.activate(isCompact ? compactConstraints : wideConstraints)
		}
		super.layout()
	}
}

/// Intercepts image paste/drop while retaining ordinary text editing and file drops.
final class ContextComposerTextView: NSTextView
{
	var onImage: ((NSImage, String) -> Void)?
	var acceptsImageAttachments = true
	var imagePasteboard: NSPasteboard = .general
	var placeholder = "Message Codex…"
	{
		didSet
		{
			needsDisplay = true
		}
	}

	override var string: String
	{
		didSet
		{
			needsDisplay = true
		}
	}

	override func didChangeText()
	{
		super.didChangeText()
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		super.draw(dirtyRect)
		guard string.isEmpty
		else
		{
			return
		}
		let origin = textContainerOrigin
		(placeholder as NSString).draw(
			at: origin,
			withAttributes: [
				.font: font ?? NSFont.systemFont(ofSize: 15),
				.foregroundColor: NSColor.placeholderTextColor,
			]
		)
	}

	override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool
	{
		if menuItem.action == #selector(NSText.paste(_:)), canPasteImage
		{
			return true
		}
		return super.validateMenuItem(menuItem)
	}

	override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool
	{
		if item.action == #selector(NSText.paste(_:)), canPasteImage
		{
			return true
		}
		return super.validateUserInterfaceItem(item)
	}

	private var canPasteImage: Bool
	{
		isEditable && acceptsImageAttachments && onImage != nil
			&& NSImage(pasteboard: imagePasteboard) != nil
	}

	override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation
	{
		if isEditable, acceptsImageAttachments, onImage != nil,
			draggedImage(from: sender.draggingPasteboard) != nil
		{
			return .copy
		}
		return super.draggingEntered(sender)
	}

	override func paste(_ sender: Any?)
	{
		if isEditable, acceptsImageAttachments, let onImage,
			let image = NSImage(pasteboard: imagePasteboard)
		{
			onImage(
				image,
				"Pasted image"
			)
			return
		}
		super.paste(sender)
	}

	override func performDragOperation(_ sender: NSDraggingInfo) -> Bool
	{
		if isEditable, acceptsImageAttachments, let onImage,
			let (image, title) = draggedImage(from: sender.draggingPasteboard)
		{
			onImage(
				image,
				title
			)
			return true
		}
		return super.performDragOperation(sender)
	}

	private func draggedImage(from pasteboard: NSPasteboard) -> (NSImage, String)?
	{
		if let url =
			(pasteboard.readObjects(
				forClasses: [NSURL.self],
				options: [
					.urlReadingFileURLsOnly: true
				]
			) as? [URL])?.first,
			let image = NSImage(contentsOf: url)
		{
			return (image, url.lastPathComponent)
		}
		if let image = NSImage(pasteboard: pasteboard)
		{
			return (image, "Dropped image")
		}
		return nil
	}
}

struct ProjectFileIndex
{
	let files: [String]

	static func load(projectPath: String) -> ProjectFileIndex
	{
		let projectRoot = URL(fileURLWithPath: projectPath)
		let ignoredDirectories: Set<String> = [
			".git",
			".build",
			"node_modules",
			"DerivedData",
			"build",
			"dist",
			".next",
		]
		guard let enumerator = FileManager.default.enumerator(atPath: projectRoot.path)
		else
		{
			return ProjectFileIndex(files: [])
		}
		var files: [String] = []
		while let relativePath = enumerator.nextObject() as? String, files.count < 50_000
		{
			if Task.isCancelled
			{
				break
			}
			let name = URL(fileURLWithPath: relativePath).lastPathComponent
			var isDirectory: ObjCBool = false
			let exists = FileManager.default.fileExists(
				atPath: projectRoot.appendingPathComponent(relativePath).path,
				isDirectory: &isDirectory
			)
			guard exists
			else
			{
				continue
			}
			if isDirectory.boolValue
			{
				let shouldSkipDirectory = name.hasPrefix(".") || ignoredDirectories.contains(name)
					|| name.hasSuffix(".app") || name.hasSuffix(".xcodeproj")
				if shouldSkipDirectory
				{
					enumerator.skipDescendants()
				}
				continue
			}
			guard !name.hasPrefix(".")
			else
			{
				continue
			}
			files.append(relativePath)
		}
		return ProjectFileIndex(files: files.sorted())
	}

	func search(
		_ query: String,
		limit: Int = 12
	) -> [String]
	{
		let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		guard !normalizedQuery.isEmpty
		else
		{
			return Array(files.prefix(limit))
		}
		return files.compactMap
		{
			path -> (path: String, score: Int)? in
			let lowercasedPath = path.lowercased()
			let fileName = URL(fileURLWithPath: path).lastPathComponent.lowercased()
			let score: Int
			if fileName == normalizedQuery
			{
				score = 0
			}
			else if fileName.hasPrefix(normalizedQuery)
			{
				score = 1
			}
			else if fileName.contains(normalizedQuery)
			{
				score = 2
			}
			else if lowercasedPath.hasPrefix(normalizedQuery)
			{
				score = 3
			}
			else if lowercasedPath.contains(normalizedQuery)
			{
				score = 4
			}
			else
			{
				return nil
			}
			return (path, score)
		}
		.sorted
		{
			left, right in
			left.score == right.score
				? left.path.count < right.path.count
				: left.score < right.score
		}
		.prefix(limit)
		.map(\.path)
	}
}

@MainActor
final class ComposerContextView: NSView
{
	var onRemove: ((String) -> Void)?
	var onReuse: ((String) -> Void)?

	private let itemStack = NSStackView()
	private let reuseButton = NSPopUpButton()
	private var reusable: [ComposerContextItem] = []

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		itemStack.orientation = .vertical
		itemStack.alignment = .leading
		itemStack.spacing = 8
		itemStack.isHidden = true

		reuseButton.target = self
		reuseButton.action = #selector(reuseSelected)
		DesktopTheme.stylePopup(reuseButton)
		reuseButton.setAccessibilityLabel("Reuse a reference from an earlier message")
		reuseButton.isHidden = true

		let stack = NSStackView(views: [itemStack, reuseButton])
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = 5
		stack.translatesAutoresizingMaskIntoConstraints = false

		addSubview(stack)
		isHidden = true

		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor),
			stack.topAnchor.constraint(equalTo: topAnchor),
			stack.bottomAnchor.constraint(equalTo: bottomAnchor),
			itemStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
		])
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func render(
		items: [ComposerContextItem],
		reusable: [ComposerContextItem]
	)
	{
		guard currentItems != items || self.reusable != reusable
		else
		{
			return
		}

		currentItems = items
		rebuildItemRows(items)
		itemStack.isHidden = items.isEmpty

		if self.reusable != reusable
		{
			self.reusable = reusable
			rebuildReuseMenu(reusable)
		}

		reuseButton.isHidden = reusable.isEmpty
		isHidden = items.isEmpty && reusable.isEmpty
	}

	private func rebuildItemRows(_ items: [ComposerContextItem])
	{
		for itemRow in itemStack.arrangedSubviews
		{
			itemStack.removeArrangedSubview(itemRow)
			itemRow.removeFromSuperview()
		}

		for item in items
		{
			let itemRow = makeContextRow(for: item)
			itemStack.addArrangedSubview(itemRow)
			itemRow.widthAnchor.constraint(equalTo: itemStack.widthAnchor).isActive = true
		}
	}

	private func rebuildReuseMenu(_ items: [ComposerContextItem])
	{
		reuseButton.removeAllItems()
		reuseButton.addItem(withTitle: "Reuse Earlier Reference…")
		for item in items.reversed()
		{
			reuseButton.addItem(withTitle: "\(item.kind.title) · \(item.detail)")
			reuseButton.lastItem?.representedObject = item.id
		}
	}

	private func makeContextRow(for item: ComposerContextItem) -> NSView
	{
		var rowContents: [NSView] = []

		if let imagePreview = makeImagePreview(for: item)
		{
			rowContents.append(imagePreview)
		}

		rowContents.append(makeDescriptionLabel(for: item))
		rowContents.append(makeInspectButton(for: item))
		rowContents.append(makeRemoveButton(for: item))

		let contextRow = NSStackView(views: rowContents)

		contextRow.orientation = .horizontal
		contextRow.alignment = .centerY
		contextRow.spacing = 6
		contextRow.setAccessibilityLabel("\(item.kind.title): \(item.detail)")

		return contextRow
	}

	private func makeImagePreview(for item: ComposerContextItem) -> NSImageView?
	{
		guard item.kind == .image,
				let path = item.path,
				let image = NSImage(contentsOfFile: path)
		else
		{
			return nil
		}

		let imagePreview = NSImageView(image: image)

		imagePreview.imageScaling = .scaleProportionallyUpOrDown
		imagePreview.widthAnchor.constraint(equalToConstant: 120).isActive = true
		imagePreview.heightAnchor.constraint(equalToConstant: 120).isActive = true

		imagePreview.wantsLayer = true
		imagePreview.layer?.cornerRadius = 6
		imagePreview.layer?.masksToBounds = true
		imagePreview.setAccessibilityLabel("Preview of attached image \(item.title)")

		return imagePreview
	}

	private func makeDescriptionLabel(for item: ComposerContextItem) -> NSTextField
	{
		let descriptionLabel = NSTextField(
			wrappingLabelWithString: "\(item.kind.title): \(item.detail)"
		)

		descriptionLabel.font = .systemFont(ofSize: 12)
		descriptionLabel.textColor = .secondaryLabelColor

		descriptionLabel.lineBreakMode = .byTruncatingMiddle
		descriptionLabel.maximumNumberOfLines = 2

		// Let the description yield horizontal space to the preview and action buttons.
		descriptionLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)

		descriptionLabel.toolTip = "\(item.kind.title): \(item.detail)"
		descriptionLabel.setAccessibilityLabel(
			"Attached \(item.kind.title.lowercased()): \(item.detail)"
		)

		return descriptionLabel
	}

	private func makeInspectButton(for item: ComposerContextItem) -> NSButton
	{
		let inspectButton = NSButton(
			title: "Inspect",
			target: self,
			action: #selector(inspectItem(_:))
		)

		DesktopTheme.styleButton(
			inspectButton,
			icon: .infoCircle
		)

		inspectButton.imagePosition = .imageOnly
		inspectButton.widthAnchor.constraint(equalToConstant: 24).isActive = true
		inspectButton.identifier = NSUserInterfaceItemIdentifier(item.id)
		inspectButton.setAccessibilityLabel("Inspect \(item.kind.title.lowercased()) \(item.title)")

		return inspectButton
	}

	private func makeRemoveButton(for item: ComposerContextItem) -> NSButton
	{
		let removeButton = NSButton(
			title: "Remove",
			target: self,
			action: #selector(removeItem(_:))
		)

		DesktopTheme.styleButton(
			removeButton,
			icon: .xCircle
		)

		removeButton.imagePosition = .imageOnly
		removeButton.widthAnchor.constraint(equalToConstant: 24).isActive = true
		removeButton.identifier = NSUserInterfaceItemIdentifier(item.id)
		removeButton.setAccessibilityLabel("Remove \(item.kind.title.lowercased()) \(item.title)")

		return removeButton
	}

	@objc private func removeItem(_ sender: NSButton)
	{
		guard let id = sender.identifier?.rawValue
		else
		{
			return
		}
		onRemove?(id)
	}

	@objc private func inspectItem(_ sender: NSButton)
	{
		guard let id = sender.identifier?.rawValue,
				let item = currentItems.first(where:
				{
					$0.id == id
				}),
				let window = window
		else
		{
			return
		}

		let alert = NSAlert()
		alert.messageText = "\(item.kind.title): \(item.detail)"
		alert.addButton(withTitle: "Close")

		if item.kind == .image, let path = item.path,
			let image = NSImage(contentsOfFile: path)
		{
			let preview = NSImageView(image: image)
			preview.imageScaling = .scaleProportionallyUpOrDown
			preview.frame = NSRect(
				x: 0,
				y: 0,
				width: 400,
				height: 280
			)
			alert.accessoryView = preview
		}
		else if let excerpt = item.excerpt
		{
			alert.accessoryView =
				ScrollableTextPreview.make(
					text: excerpt,
					size: NSSize(
						width: 440,
						height: 220
					),
					font: .monospacedSystemFont(
						ofSize: 12,
						weight: .regular
					),
					accessibilityLabel: "Attached code excerpt"
				).scrollView
		}

		alert.beginSheetModal(for: window)
	}

	private var currentItems: [ComposerContextItem] = []

	@objc private func reuseSelected()
	{
		guard let id = reuseButton.selectedItem?.representedObject as? String
		else
		{
			return
		}
		onReuse?(id)
		reuseButton.selectItem(at: 0)
	}
}
