import AppKit

/// Shows only backend-reported edits; the review button retains this item's exact diff.
@MainActor
final class ConversationFileChangeCollectionItem: NSCollectionViewItem
{
	private let titleLabel = FileChangeTextField(labelWithString: "")
	private let counts = FileChangeTextField(labelWithString: "")
	private let review = FileChangeReviewButton(
		title: "View changes",
		target: nil,
		action: nil
	)
	private var changes: [FileChange] = []
	private var popover: NSPopover?

	override func loadView()
	{
		view = DesktopSurface(
			NSColor(name: nil)
			{
				appearance in
				appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
					? NSColor(
						white: 34.0 / 255,
						alpha: 1
					) : DesktopTheme.elevated
			},
			cornerRadius: 10,
			bordered: true,
			borderWidth: 0.5
		)
		let iconSurface = DesktopSurface(
			DesktopTheme.canvas,
			cornerRadius: 10
		)
		let icon = FileChangeIconView()
		icon.translatesAutoresizingMaskIntoConstraints = false
		iconSurface.addSubview(icon)
		NSLayoutConstraint.activate([
			iconSurface.widthAnchor.constraint(equalToConstant: 40),
			iconSurface.heightAnchor.constraint(equalToConstant: 40),
			icon.centerXAnchor.constraint(equalTo: iconSurface.centerXAnchor),
			icon.centerYAnchor.constraint(equalTo: iconSurface.centerYAnchor),
			icon.widthAnchor.constraint(equalToConstant: 20),
			icon.heightAnchor.constraint(equalToConstant: 20),
		])
		titleLabel.font = .systemFont(
			ofSize: 14,
			weight: .medium
		)
		titleLabel.textColor = ConversationAttributedStringRenderer.proseColor
		titleLabel.lineBreakMode = .byTruncatingMiddle
		titleLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		counts.font = .systemFont(ofSize: 13)
		let labels = NSStackView(views: [titleLabel, counts])
		labels.orientation = .vertical
		labels.alignment = .leading
		labels.spacing = 4
		let spacer = NSView()
		spacer.setContentHuggingPriority(
			.defaultLow,
			for: .horizontal
		)
		review.target = self
		review.action = #selector(showChanges)
		review.bezelStyle = .inline
		review.isBordered = false
		review.wantsLayer = true
		review.layer?.cornerRadius = 10
		review.layer?.borderWidth = 1
		review.layer?.borderColor = DesktopTheme.border.cgColor
		review.contentTintColor = ConversationAttributedStringRenderer.proseColor
		review.widthAnchor.constraint(equalToConstant: 102).isActive = true
		review.heightAnchor.constraint(equalToConstant: 28).isActive = true
		review.font = .systemFont(ofSize: 13)
		let row = NSStackView(views: [iconSurface, labels, spacer, review])
		row.spacing = 10
		row.alignment = .centerY
		row.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(row)
		NSLayoutConstraint.activate([
			row.leadingAnchor.constraint(
				equalTo: view.leadingAnchor,
				constant: 12
			),
			row.trailingAnchor.constraint(
				equalTo: view.trailingAnchor,
				constant: -12
			),
			row.centerYAnchor.constraint(equalTo: view.centerYAnchor),
		])
	}

	func configure(
		_ changes: [FileChange],
		status: String
	)
	{
		_ = view
		popover?.close()
		popover = nil
		self.changes = changes
		let names = changes.map
		{
			URL(fileURLWithPath: $0.path).lastPathComponent
		}
		let prefix = status == "completed" ? "Edited" : "File changes · \(status)"
		if names.count == 1
		{
			titleLabel.stringValue = "\(prefix) \(names[0])"
		}
		else
		{
			titleLabel.stringValue = "\(prefix) \(names.count) files"
		}
		titleLabel.toolTip = changes.map(\.path).joined(separator: "\n")
		let diff = changes.map(\.diff).joined(separator: "\n")
		let lines = diff.split(separator: "\n")
		let additions = lines.filter
		{
			$0.hasPrefix("+") && !$0.hasPrefix("+++")
		}.count
		let deletions = lines.filter
		{
			$0.hasPrefix("-") && !$0.hasPrefix("---")
		}.count
		let summary = NSMutableAttributedString(
			string: "+\(additions)",
			attributes: [.foregroundColor: NSColor.systemGreen]
		)
		summary.append(NSAttributedString(
			string: " -\(deletions)",
			attributes: [.foregroundColor: NSColor.systemRed]
		))
		counts.attributedStringValue = summary
		counts.isHidden = diff.isEmpty
		review.isEnabled = !diff.isEmpty
		view.setAccessibilityLabel(titleLabel.stringValue)
	}

	@objc private func showChanges()
	{
		let text = changes.map
		{
			"\($0.path)\n\($0.diff)"
		}.joined(separator: "\n\n")
		let preview = ScrollableTextPreview.make(
			text: text,
			size: NSSize(
				width: 640,
				height: 420
			),
			font: .monospacedSystemFont(
				ofSize: 12,
				weight: .regular
			),
			accessibilityLabel: "Reported file changes"
		)
		let controller = NSViewController()
		controller.view = preview.scrollView
		let popover = NSPopover()
		popover.behavior = .transient
		popover.contentViewController = controller
		popover.contentSize = NSSize(
			width: 640,
			height: 420
		)
		self.popover = popover
		popover.show(
			relativeTo: review.bounds,
			of: review,
			preferredEdge: .minY
		)
	}
}

@MainActor
private final class FileChangeTextField: NSTextField
{
	override func draw(_ dirtyRect: NSRect)
	{
		ConversationTextDrawing.withAntialiasing
		{
			super.draw(dirtyRect)
		}
	}
}

@MainActor
private final class FileChangeReviewButton: NSButton
{
	override func draw(_ dirtyRect: NSRect)
	{
		ConversationTextDrawing.withAntialiasing
		{
			super.draw(dirtyRect)
		}
	}
}

/// The reference uses an unfurled document with the plus inside its outline.
@MainActor
private final class FileChangeIconView: NSView
{
	override func draw(_ dirtyRect: NSRect)
	{
		NSColor.secondaryLabelColor.setStroke()
		let outline = NSBezierPath(
			roundedRect: bounds.insetBy(
				dx: 2,
				dy: 2
			),
			xRadius: 2.5,
			yRadius: 2.5
		)
		outline.lineWidth = 1.5
		outline.stroke()
		let marks = NSBezierPath()
		marks.lineWidth = 1.5
		marks.lineCapStyle = .round
		marks.move(to: NSPoint(
			x: 7,
			y: 11
		))
		marks.line(to: NSPoint(
			x: 13,
			y: 11
		))
		marks.move(to: NSPoint(
			x: 10,
			y: 8
		))
		marks.line(to: NSPoint(
			x: 10,
			y: 14
		))
		marks.move(to: NSPoint(
			x: 7,
			y: 6
		))
		marks.line(to: NSPoint(
			x: 13,
			y: 6
		))
		marks.stroke()
	}
}
