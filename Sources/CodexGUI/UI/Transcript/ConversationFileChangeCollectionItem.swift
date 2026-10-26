import AppKit

/// Shows backend-reported edits and opens the shared Changes tool through its host.
@MainActor
final class ConversationFileChangeCollectionItem: NSCollectionViewItem
{
	private let titleLabel = FileChangeTextField(labelWithString: "")
	private let counts = DesktopDiffStats(
		counts: DesktopDiffStats.Counts(
			additions: 0,
			deletions: 0
		),
		presentation: .transcript
	)
	private let fileList = NSStackView()
	private let separator = NSBox()
	private let disclosure = DesktopDisclosureButton(presentation: .fileList)
	private var onToggle: (() -> Void)?
	private let review = DesktopFileChangeReviewButton()
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
					) : AppKitColorTokens.elevated
			},
			cornerRadius: 10,
			bordered: true,
			borderWidth: 0.5
		)
		let iconSurface = DesktopSurface(
			AppKitColorTokens.canvas,
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
		titleLabel.textColor = MarkdownAttributedStringRenderer.proseColor
		titleLabel.lineBreakMode = .byTruncatingMiddle
		titleLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		let labels = AppKitLayout.verticalStack(
			[titleLabel, counts],
			spacing: 4,
			alignment: .leading
		)
		let spacer = NSView()
		spacer.setContentHuggingPriority(
			.defaultLow,
			for: .horizontal
		)
		review.target = self
		review.action = #selector(showChanges)
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
		disclosure.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(disclosure)
		NSLayoutConstraint.activate([
			disclosure.topAnchor.constraint(equalTo: fileList.bottomAnchor),
			disclosure.leadingAnchor.constraint(
				equalTo: view.leadingAnchor,
				constant: 12
			),
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
					DesktopDisclosureButton.collapsedFileCount,
					changes.count
				)) * 36
				+ (changes.count > DesktopDisclosureButton.collapsedFileCount
					? DesktopDisclosureButton.Presentation.fileList.rowHeight : 0)
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
		disclosure.configureFileList(
			count: changes.count,
			expanded: expanded
		)
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
		counts.update(Self.lineCounts(for: diff))
		counts.isHidden = diff.isEmpty
		review.isEnabled = onViewChanges != nil
		for row in fileList.arrangedSubviews
		{
			fileList.removeArrangedSubview(row)
			row.removeFromSuperview()
		}
		separator.isHidden = changes.isEmpty
		for change in changes
			.prefix(expanded ? changes.count : DesktopDisclosureButton.collapsedFileCount)
		{
			appendFileRow(
				change,
				projectPath: projectPath
			)
		}
		view.setAccessibilityLabel(titleLabel.stringValue)
	}

	private func appendFileRow(
		_ change: FileChange,
		projectPath: String?
	)
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

		let row = DesktopResourceRow(
			title: path,
			icon: WorkspaceFileIcon.image(relativePath: path),
			diffStats: change.diff.isEmpty ? nil : Self.lineCounts(for: change.diff),
			presentation: .file
		)
		row.titleLabel.toolTip = change.path
		fileList.addArrangedSubview(row)
		row.widthAnchor.constraint(equalTo: fileList.widthAnchor).isActive = true
	}

	@objc private func toggleFiles()
	{
		onToggle?()
	}

	private static func lineCounts(for diff: String) -> DesktopDiffStats.Counts
	{
		let parsed = GitDiffParser.lineCounts(in: diff)
		return DesktopDiffStats.Counts(
			additions: parsed.additions,
			deletions: parsed.deletions
		)
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
		MarkdownTextDrawing.withAntialiasing
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
