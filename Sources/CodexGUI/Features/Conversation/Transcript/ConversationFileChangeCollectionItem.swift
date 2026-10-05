import AppKit

/// Shows backend-reported edits and opens the shared Changes tool through its host.
@MainActor
final class ConversationFileChangeCollectionItem: NSCollectionViewItem
{
	private let titleLabel = FileChangeTextField(labelWithString: "")
	private let counts = FileChangeTextField(labelWithString: "")
	private let fileList = NSStackView()
	private let separator = NSBox()
	private let disclosure = FileChangeReviewButton(
		title: "",
		target: nil,
		action: nil
	)
	private var onToggle: (() -> Void)?
	private let review = FileChangeReviewButton(
		title: "View changes",
		target: nil,
		action: nil
	)
	private var onViewChanges: (() -> Void)?

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
			row.centerYAnchor.constraint(
				equalTo: view.topAnchor,
				constant: 33
			),
		])
		separator.boxType = .separator
		separator.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(separator)
		fileList.orientation = .vertical
		fileList.alignment = .leading
		fileList.spacing = 0
		fileList.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(fileList)
		NSLayoutConstraint.activate([
			separator.topAnchor.constraint(
				equalTo: view.topAnchor,
				constant: 66
			),
			separator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			separator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			separator.heightAnchor.constraint(equalToConstant: 1),
			fileList.topAnchor.constraint(equalTo: separator.bottomAnchor),
			fileList.leadingAnchor.constraint(
				equalTo: view.leadingAnchor,
				constant: 12
			),
			fileList.trailingAnchor.constraint(
				equalTo: view.trailingAnchor,
				constant: -12
			),
		])
		disclosure.target = self
		disclosure.action = #selector(toggleFiles)
		disclosure.isBordered = false
		disclosure.alignment = .left
		disclosure.font = .systemFont(ofSize: 13)
		disclosure.contentTintColor = ConversationAttributedStringRenderer.proseColor
		disclosure.imagePosition = .imageRight
		disclosure.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(disclosure)
		NSLayoutConstraint.activate([
			disclosure.topAnchor.constraint(equalTo: fileList.bottomAnchor),
			disclosure.leadingAnchor.constraint(
				equalTo: view.leadingAnchor,
				constant: 12
			),
			disclosure.heightAnchor.constraint(equalToConstant: 36),
		])
	}

	static func itemSize(
		changes: [FileChange],
		width: CGFloat,
		expanded: Bool = false
	) -> NSSize
	{
		NSSize(
			width: width,
			height: changes.isEmpty ? 66 : 75
				+ CGFloat(expanded ? changes.count : min(
					3,
					changes.count
				)) * 36
				+ (changes.count > 3 ? 36 : 0)
		)
	}

	func configure(
		_ changes: [FileChange],
		status: String,
		projectPath: String? = nil,
		expanded: Bool = false,
		onViewChanges: (() -> Void)? = nil,
		onToggle: (() -> Void)? = nil
	)
	{
		_ = view
		self.onViewChanges = onViewChanges
		self.onToggle = onToggle
		disclosure.isHidden = changes.count <= 3
		let remaining = max(
			0,
			changes.count - 3
		)
		disclosure.title = expanded ? "Collapse files" :
			"Show \(remaining) more \(remaining == 1 ? "file" : "files")"
		disclosure.image = NSImage(
			systemSymbolName: expanded ? "chevron.up" : "chevron.down",
			accessibilityDescription: nil
		)
		disclosure.setAccessibilityLabel(disclosure.title)
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
		counts.attributedStringValue = Self.lineCounts(for: diff)
		counts.isHidden = diff.isEmpty
		review.isEnabled = onViewChanges != nil
		for row in fileList.arrangedSubviews
		{
			fileList.removeArrangedSubview(row)
			row.removeFromSuperview()
		}
		separator.isHidden = changes.isEmpty
		for change in changes.prefix(expanded ? changes.count : 3)
		{
			var path = change.path
			if let projectPath
			{
				let prefix = projectPath.hasSuffix("/") ? projectPath : projectPath + "/"
				if path.hasPrefix(prefix)
				{
					path = String(path.dropFirst(prefix.count))
				}
			}
			let name = FileChangeTextField(labelWithString: path)
			name.font = .systemFont(ofSize: 13)
			name.textColor = ConversationAttributedStringRenderer.proseColor
			name.lineBreakMode = .byTruncatingMiddle
			name.toolTip = change.path
			name.setContentHuggingPriority(
				.defaultLow,
				for: .horizontal
			)
			name.setContentCompressionResistancePriority(
				.defaultLow,
				for: .horizontal
			)
			let fileCounts = FileChangeTextField(labelWithString: "")
			fileCounts.font = .systemFont(ofSize: 13)
			fileCounts.attributedStringValue = Self.lineCounts(for: change.diff)
			fileCounts.isHidden = change.diff.isEmpty
			fileCounts.setContentCompressionResistancePriority(
				.required,
				for: .horizontal
			)
			let row = NSView()
			row.translatesAutoresizingMaskIntoConstraints = false
			name.translatesAutoresizingMaskIntoConstraints = false
			fileCounts.translatesAutoresizingMaskIntoConstraints = false
			row.addSubview(name)
			row.addSubview(fileCounts)
			fileList.addArrangedSubview(row)
			NSLayoutConstraint.activate([
				row.widthAnchor.constraint(equalTo: fileList.widthAnchor),
				row.heightAnchor.constraint(equalToConstant: 36),
				name.leadingAnchor.constraint(equalTo: row.leadingAnchor),
				name.centerYAnchor.constraint(equalTo: row.centerYAnchor),
				name.trailingAnchor.constraint(
					lessThanOrEqualTo: fileCounts.leadingAnchor,
					constant: -12
				),
				fileCounts.trailingAnchor.constraint(equalTo: row.trailingAnchor),
				fileCounts.centerYAnchor.constraint(equalTo: row.centerYAnchor),
			])
		}
		view.setAccessibilityLabel(titleLabel.stringValue)
	}

	@objc private func toggleFiles()
	{
		onToggle?()
	}

	private static func lineCounts(for diff: String) -> NSAttributedString
	{
		let parsed = GitDiffParser.hunks(in: diff.components(separatedBy: "\n"))
		let additions = parsed.additions
		let deletions = parsed.deletions
		let summary = NSMutableAttributedString(
			string: "+\(additions)",
			attributes: [.foregroundColor: NSColor.systemGreen]
		)
		summary.append(NSAttributedString(
			string: " -\(deletions)",
			attributes: [.foregroundColor: NSColor.systemRed]
		))
		return summary
	}

	@objc private func showChanges()
	{
		onViewChanges?()
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
