import AppKit

@MainActor
final class ComposerContextView: NSView
{
	var onRemove: ((String) -> Void)?

	private let itemStack = NSStackView()
	private let expandedPreview = ExpandedImagePreview()
	private var renderedImageColumnCount = 1
	private var itemRowsByID: [String: NSView] = [:]
	private static let imageRowSpacing: CGFloat = 8

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)

		itemStack.orientation = .vertical
		itemStack.alignment = .leading
		itemStack.spacing = 8

		AppKitLayout.pin(
			itemStack,
			to: self,
			inset: 0
		)
		isHidden = true
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func render(items: [ComposerContextItem])
	{
		guard currentItems != items
		else
		{
			return
		}

		expandedPreview.dismiss()
		currentItems = items
		itemRowsByID.removeAll()
		rebuildItemRows(items)
		isHidden = items.isEmpty
	}

	override func viewWillMove(toWindow newWindow: NSWindow?)
	{
		if newWindow !== window
		{
			expandedPreview.dismiss()
		}
		super.viewWillMove(toWindow: newWindow)
	}

	func waitForExpandedPreview() async
	{
		await expandedPreview.waitForPresentation()
	}

	private func rebuildItemRows(_ items: [ComposerContextItem])
	{
		for itemRow in itemStack.arrangedSubviews
		{
			itemStack.removeArrangedSubview(itemRow)
			itemRow.removeFromSuperview()
		}

		renderedImageColumnCount = imageColumnCount
		var imageRow: NSView?
		var imagesInRow = 0
		for item in items
		{
			let itemRow: NSView
			if let existingRow = itemRowsByID[item.id]
			{
				itemRow = existingRow
				itemRow.removeFromSuperview()
			}
			else
			{
				itemRow = makeContextRow(for: item)
				itemRowsByID[item.id] = itemRow
				if item.kind == .image
				{
					itemRow.widthAnchor.constraint(
						equalToConstant: ComposerImageAttachmentView.sideLength
					).isActive = true
				}
			}
			if item.kind == .image
			{
				if imageRow == nil || imagesInRow == renderedImageColumnCount
				{
					let row = NSView()
					itemStack.addArrangedSubview(row)
					row.widthAnchor.constraint(equalTo: itemStack.widthAnchor).isActive = true
					imageRow = row
					imagesInRow = 0
				}
				if let imageRow
				{
					itemRow.translatesAutoresizingMaskIntoConstraints = false
					imageRow.addSubview(itemRow)
					let offset = CGFloat(imagesInRow)
						* (ComposerImageAttachmentView.sideLength + Self.imageRowSpacing)
					NSLayoutConstraint.activate([
						itemRow.leadingAnchor.constraint(
							equalTo: imageRow.leadingAnchor,
							constant: offset
						),
						itemRow.topAnchor.constraint(equalTo: imageRow.topAnchor),
						itemRow.bottomAnchor.constraint(equalTo: imageRow.bottomAnchor),
					])
				}
				imagesInRow += 1
			}
			else
			{
				imageRow = nil
				imagesInRow = 0
				itemStack.addArrangedSubview(itemRow)
				itemRow.widthAnchor.constraint(equalTo: itemStack.widthAnchor).isActive = true
			}
		}
	}

	private var imageColumnCount: Int
	{
		max(
			1,
			Int((bounds.width + Self.imageRowSpacing)
				/ (ComposerImageAttachmentView.sideLength + Self.imageRowSpacing))
		)
	}

	override func layout()
	{
		super.layout()
		if renderedImageColumnCount != imageColumnCount
		{
			rebuildItemRows(currentItems)
			super.layout()
		}
	}

	private func makeContextRow(for item: ComposerContextItem) -> NSView
	{
		var rowContents: [NSView] = []

		if item.kind == .image
		{
			let previewButton = NSButton(
				title: "Expand image",
				target: self,
				action: #selector(inspectItem(_:))
			)
			previewButton.identifier = NSUserInterfaceItemIdentifier(item.id)
			previewButton.setAccessibilityLabel("Expand attached image \(item.title)")

			let attachment = ComposerImageAttachmentView(
				image: item.path.flatMap
				{
					NSImage(contentsOfFile: $0)
				},
				previewButton: previewButton,
				removeButton: makeRemoveButton(for: item)
			)

			let row = NSView()
			attachment.translatesAutoresizingMaskIntoConstraints = false
			row.addSubview(attachment)
			NSLayoutConstraint.activate([
				attachment.leadingAnchor.constraint(equalTo: row.leadingAnchor),
				attachment.topAnchor.constraint(equalTo: row.topAnchor),
				attachment.bottomAnchor.constraint(equalTo: row.bottomAnchor),
			])
			return row
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

		AppKitControlStyling.styleButton(
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

		AppKitControlStyling.styleButton(
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
		guard let id = sender.identifier?.rawValue,
				let row = itemRowsByID[id], sender.isDescendant(of: row)
		else
		{
			return
		}
		onRemove?(id)
	}

	@objc private func inspectItem(_ sender: NSButton)
	{
		guard let id = sender.identifier?.rawValue,
				let row = itemRowsByID[id], sender.isDescendant(of: row),
				let item = currentItems.first(where:
				{
					$0.id == id
				}),
				let window = window
		else
		{
			return
		}

		if item.kind == .image
		{
			guard let path = item.path
			else
			{
				return
			}
			expandedPreview.present(
				path: path,
				name: item.title,
				in: window
			)
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
		if let excerpt = item.excerpt
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
}
