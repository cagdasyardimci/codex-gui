import AppKit

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
		let contextChanged = currentItems != items || self.reusable != reusable
		guard contextChanged
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

		alert.accessoryView = makeInspectionAccessory(for: item)

		alert.beginSheetModal(for: window)
	}

	private func makeInspectionAccessory(for item: ComposerContextItem) -> NSView?
	{
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
			return preview
		}
		else if let excerpt = item.excerpt
		{
			return ScrollableTextPreview.make(
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
		return nil
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
