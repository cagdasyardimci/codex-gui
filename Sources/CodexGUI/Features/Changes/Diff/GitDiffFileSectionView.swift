import AppKit

/// Renders one file header and its visible diff chunks; actions return to the host controller.
@MainActor
final class GitDiffFileSectionView: NSStackView
{
	private enum GapLayout
	{
		static let controlHeight: CGFloat = 16
		static let controlWidth: CGFloat = 52
		static let dividerThickness: CGFloat = 1
		static let rowHeight = controlHeight * 2 + dividerThickness
	}

	private(set) var diffViews: [GitAdaptiveDiffView] = []
	private let onToggleFileDiff: (NSButton) -> Void
	private let onExpandGap: (NSButton) -> Void
	private let onRichPreview: (NSButton) -> Void
	private var previewButton: NSButton?
	private var richPreviewView: GitRichPreviewView?
	private let filePath: String

	init(
		file: GitComparisonFile,
		rows: [GitDiffRow]?,
		isCollapsed: Bool,
		layoutPreference: GitDiffLayoutPreference,
		wrapsCode: Bool,
		onToggleFileDiff: @escaping (NSButton) -> Void,
		onExpandGap: @escaping (NSButton) -> Void,
		onRichPreview: @escaping (NSButton) -> Void
	)
	{
		self.onToggleFileDiff = onToggleFileDiff
		self.onExpandGap = onExpandGap
		self.onRichPreview = onRichPreview
		filePath = file.path
		super.init(frame: .zero)
		render(
			file: file,
			rows: rows,
			isCollapsed: isCollapsed,
			layoutPreference: layoutPreference,
			wrapsCode: wrapsCode
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	@objc private func toggleFileDiff(_ sender: NSButton)
	{
		onToggleFileDiff(sender)
	}

	@objc private func expandGap(_ sender: NSButton)
	{
		onExpandGap(sender)
	}

	@objc private func richPreview(_ sender: NSButton)
	{
		onRichPreview(sender)
	}

	func toggleRichPreview(makePreview: () -> GitRichPreviewView)
	{
		if let preview = richPreviewView
		{
			preview.cancelLoading()
			removeArrangedSubview(preview)
			preview.removeFromSuperview()
			richPreviewView = nil
			for body in arrangedSubviews.dropFirst(2)
			{
				body.isHidden = false
			}
			previewButton?.state = .off
			previewButton?.contentTintColor = .secondaryLabelColor
			previewButton?.toolTip = "Rich preview of the compared file version"
			previewButton?.setAccessibilityLabel("Rich preview of \(filePath)")
		}
		else
		{
			for body in arrangedSubviews.dropFirst(2)
			{
				body.isHidden = true
			}
			let preview = makePreview()
			richPreviewView = preview
			addArrangedSubview(preview)
			preview.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
			previewButton?.state = .on
			previewButton?.contentTintColor = .systemBlue
			previewButton?.toolTip = "Show diff for \(filePath)"
			previewButton?.setAccessibilityLabel("Show diff for \(filePath)")
		}
		needsLayout = true
	}

	private func render(
		file: GitComparisonFile,
		rows: [GitDiffRow]?,
		isCollapsed: Bool,
		layoutPreference: GitDiffLayoutPreference,
		wrapsCode: Bool
	)
	{
		let header = makeFileHeader(
			file: file,
			isCollapsed: isCollapsed
		)
		let divider = DesktopSurface(DesktopTheme.border)
		divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
		let stack = self
		stack.addArrangedSubview(header)
		stack.addArrangedSubview(divider)
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = 0
		header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		divider.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		func append(_ view: NSView)
		{
			stack.addArrangedSubview(view)
			view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		if isCollapsed
		{
			return
		}
		if file.isBinary
		{
			append(message("Binary file · textual preview unavailable"))
			return
		}
		if file.hunks.isEmpty
		{
			append(message("Metadata-only change · no textual hunks."))
			return
		}
		if rows?.isEmpty == true
		{
			append(message("No visible textual changes with the current display filters."))
			return
		}
		var chunk: [GitDiffRow] = []
		func appendPendingDiffChunk()
		{
			guard !chunk.isEmpty
			else
			{
				return
			}
			let diff = GitAdaptiveDiffView(
				rows: chunk,
				path: file.path
			)
			diff.layoutPreference = layoutPreference
			diff.wrapsCode = wrapsCode
			diffViews.append(diff)
			append(diff)
			chunk = []
		}
		for row in rows ?? []
		{
			if row.kind == .gap
			{
				appendPendingDiffChunk()
				append(makeContextGap(row))
			}
			else
			{
				chunk.append(row)
			}
		}
		appendPendingDiffChunk()
	}

	private func makeFileHeader(
		file: GitComparisonFile,
		isCollapsed: Bool
	) -> NSStackView
	{
		let icon = NSImageView(image: GitReviewReferenceIcons.fileImage(
			relativePath: file.path,
			size: 18
		))
		icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
		let path = makeFilePathLabel(file)
		let additions = NSTextField(labelWithString: "+\(file.additions)")
		additions.textColor = .systemGreen
		let deletions = NSTextField(labelWithString: "-\(file.deletions)")
		deletions.textColor = .systemRed
		let toggleDiff = referenceButton(
			isCollapsed ? "Expand diff for \(file.path)" : "Collapse diff for \(file.path)",
			image: GitReviewReferenceIcons.image(isCollapsed ? .chevronRight : .chevronDown),
			action: #selector(toggleFileDiff(_:))
		)
		toggleDiff.identifier = NSUserInterfaceItemIdentifier(file.id)
		var actions: [NSButton] = []
		if GitRichPreviewKind(path: file.path) != nil
		{
			let preview = referenceButton(
				"Rich preview of \(file.path)",
				image: GitReviewReferenceIcons.image(.eye),
				action: #selector(richPreview(_:))
			)
			preview.isEnabled = GitRichPreviewContent.blobID(for: file) != nil
			preview.setButtonType(.pushOnPushOff)
			preview.identifier = NSUserInterfaceItemIdentifier(file.id)
			previewButton = preview
			preview.toolTip = preview.isEnabled
				? "Rich preview of the compared file version"
				: "Rich preview unavailable: this comparison does not contain "
				+ "a complete file version"
			actions.append(preview)
		}
		actions += [
			("Open file unavailable", GitReviewReferenceIcons.Kind.openFile),
			("Code action unavailable", .code),
			("Additional file actions unavailable", .ellipsis)
		].map
		{
			label, glyph in
			let control = referenceButton(
				label,
				image: GitReviewReferenceIcons.image(glyph),
				action: nil
			)
			control.isEnabled = false
			control.toolTip = label + ": reference action has not been defined"
			return control
		}
		let header = AppKitLayout.horizontalStack(
			[icon, path, GitReviewControls.spacer(), additions, deletions, toggleDiff] + actions,
			spacing: 6
		)
		header.edgeInsets = NSEdgeInsets(
			top: 8,
			left: 10,
			bottom: 8,
			right: 10
		)
		return header
	}

	private func makeFilePathLabel(_ file: GitComparisonFile) -> NSTextField
	{
		let displayPath: String
		if let oldPath = file.oldPath, let newPath = file.newPath, oldPath != newPath
		{
			displayPath = "\(oldPath) → \(newPath)"
		}
		else
		{
			displayPath = file.path
		}

		let path = NSTextField(labelWithString: displayPath)
		path.font = .systemFont(ofSize: 13)
		let pathStyle = NSMutableParagraphStyle()
		pathStyle.lineBreakMode = .byTruncatingHead
		let pathText = NSMutableAttributedString(
			string: path.stringValue,
			attributes: [
				.font: NSFont.systemFont(ofSize: 13),
				.foregroundColor: NSColor.secondaryLabelColor,
				.paragraphStyle: pathStyle
			]
		)
		let filename = (file.path as NSString).lastPathComponent
		let filenameRange = (path.stringValue as NSString).range(
			of: filename,
			options: .backwards
		)
		if filenameRange.location != NSNotFound
		{
			pathText.addAttribute(
				.foregroundColor,
				value: NSColor.labelColor,
				range: filenameRange
			)
		}
		path.attributedStringValue = pathText
		AppKitLayout.compressHorizontally(path)
		path.lineBreakMode = .byTruncatingHead
		path.maximumNumberOfLines = 1
		path.cell?.wraps = false
		path.cell?.usesSingleLineMode = true
		path.toolTip = path.stringValue
		path.setAccessibilityLabel("\(file.kind.rawValue) file: \(path.stringValue)")
		return path
	}

	private func makeContextGap(_ row: GitDiffRow) -> NSView
	{
		let label = NSTextField(labelWithString: "\(row.hiddenLineCount) unmodified lines")
		label.textColor = .secondaryLabelColor
		label.font = .systemFont(ofSize: 13)

		let controls = makeGapExpansionControls(row)

		let verticalDivider = DesktopSurface(DesktopTheme.border)
		verticalDivider.widthAnchor.constraint(equalToConstant: GapLayout.dividerThickness)
			.isActive = true
		let fold = AppKitLayout.horizontalStack(
			[controls, verticalDivider, label, GitReviewControls.spacer()],
			spacing: 0
		)
		fold.setCustomSpacing(
			10,
			after: verticalDivider
		)
		let surface = DesktopSurface(
			DesktopTheme.elevated,
			cornerRadius: 7
		)
		AppKitLayout.pin(
			fold,
			to: surface,
			inset: 0
		)
		surface.heightAnchor.constraint(equalToConstant: GapLayout.rowHeight).isActive = true
		verticalDivider.heightAnchor.constraint(equalTo: surface.heightAnchor)
			.isActive = true
		if row.canExpand
		{
			surface.toolTip = "Both boundary controls expand "
				+ "this entire unchanged region from the same snapshot."
		}
		else
		{
			surface.toolTip = "Enable Load full files to reveal snapshot context."
		}
		return surface
	}

	private func makeGapExpansionControls(_ row: GitDiffRow) -> NSStackView
	{
		let above = button(
			"Expand all \(row.hiddenLineCount) unmodified lines from snapshot above",
			symbol: "chevron.down",
			action: #selector(expandGap(_:))
		)
		let below = button(
			"Expand all \(row.hiddenLineCount) unmodified lines from snapshot below",
			symbol: "chevron.up",
			action: #selector(expandGap(_:))
		)
		for control in [above, below]
		{
			control.identifier = row.gapID.map
			{
				NSUserInterfaceItemIdentifier($0)
			}
			control.isEnabled = row.canExpand
		}

		let horizontalDivider = DesktopSurface(DesktopTheme.border)
		horizontalDivider.heightAnchor.constraint(equalToConstant: GapLayout.dividerThickness)
			.isActive = true
		let controls = NSStackView(views: [above, horizontalDivider, below])
		controls.orientation = .vertical
		controls.alignment = .centerX
		controls.spacing = 0
		controls.widthAnchor.constraint(equalToConstant: GapLayout.controlWidth).isActive = true
		for control in [above, below]
		{
			control.widthAnchor.constraint(equalTo: controls.widthAnchor).isActive = true
			control.heightAnchor.constraint(equalToConstant: GapLayout.controlHeight)
				.isActive = true
		}
		horizontalDivider.widthAnchor.constraint(equalTo: controls.widthAnchor)
			.isActive = true
		return controls
	}

	private func referenceButton(
		_ title: String,
		image: NSImage,
		action: Selector?
	) -> NSButton
	{
		GitReviewControls.referenceButton(
			title,
			image: image,
			target: self,
			action: action
		)
	}

	private func button(
		_ title: String,
		symbol: String,
		action: Selector?
	) -> NSButton
	{
		let symbolImage = NSImage(
			systemSymbolName: symbol,
			accessibilityDescription: title
		) ?? NSImage()
		let symbolConfiguration = NSImage.SymbolConfiguration(
			pointSize: 11,
			weight: .medium
		)
		let configuredImage = symbolImage.withSymbolConfiguration(symbolConfiguration) ?? NSImage()
		let control = NSButton(
			image: configuredImage,
			target: self,
			action: action
		)
		control.isBordered = false
		control.focusRingType = .none
		control.contentTintColor = .secondaryLabelColor
		control.toolTip = title
		control.setAccessibilityLabel(title)
		return control
	}

	private func message(_ text: String) -> NSView
	{
		let label = NSTextField(wrappingLabelWithString: text)
		label.textColor = .secondaryLabelColor
		let row = AppKitLayout.horizontalStack(
			[label, GitReviewControls.spacer()],
			spacing: 0
		)
		row.edgeInsets = NSEdgeInsets(
			top: 12,
			left: 14,
			bottom: 12,
			right: 14
		)
		return row
	}
}
