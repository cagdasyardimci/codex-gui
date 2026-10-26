import AppKit

/// Complete filename/content search presentation with query, mask, results and shortcut footer.
@MainActor
final class DesktopFileSearchContentView: NSView
{
	enum Mode
	{
		case filename, content
	}

	init(
		mode: Mode,
		queryField: NSTextField,
		maskField: NSTextField,
		maskLabel: NSTextField,
		escapeButton: NSButton,
		statusLabel: NSTextField,
		keyboardHints: NSView,
		table: NSTableView
	)
	{
		super.init(frame: .zero)
		let container = self
		container.wantsLayer = true
		container.layer?.cornerRadius = ShapeTokens.FileSearch.panelRadius
		container.layer?.masksToBounds = true
		container.refreshBackground()
		queryField.placeholderString = mode == .filename
			? "Open file by name" : "Search file contents"
		queryField.setAccessibilityLabel(queryField.placeholderString ?? "Search files")
		queryField.isBordered = false
		queryField.drawsBackground = false
		queryField.focusRingType = .none
		queryField.font = AppKitFontResolver.font(TypographyTokens.FileSearch.query)
		maskField.placeholderString = "*.swift,*.md"
		maskField.setAccessibilityLabel("File mask")
		maskField.font = AppKitFontResolver.font(TypographyTokens.FileSearch.accessory)
		maskField.bezelStyle = .roundedBezel
		maskLabel.textColor = AppKitColorTokens.captionText
		maskLabel.font = AppKitFontResolver.font(TypographyTokens.FileSearch.maskLabel)
		escapeButton.setAccessibilityLabel("Close search")
		statusLabel.textColor = AppKitColorTokens.captionText
		statusLabel.font = AppKitFontResolver.font(TypographyTokens.FileSearch.footer)
		statusLabel.lineBreakMode = .byTruncatingTail
		statusLabel.setAccessibilityLabel("Search status")
		statusLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)

		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result"))
		column.resizingMask = .autoresizingMask
		table.addTableColumn(column)
		table.style = .plain
		table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
		table.headerView = nil
		table.rowHeight = mode == .content
			? LayoutTokens.FileSearch.contentRowHeight : LayoutTokens.FileSearch.filenameRowHeight
		table.backgroundColor = .clear
		table.intercellSpacing = NSSize(
			width: 0,
			height: 0
		)
		table.selectionHighlightStyle = .regular
		table.setAccessibilityLabel("File search results")
		let scroll = NSScrollView()
		scroll.documentView = table
		scroll.hasVerticalScroller = true
		scroll.autohidesScrollers = true
		scroll.drawsBackground = false
		let header = NSView()
		let footer = NSView()
		let divider = NSBox()
		divider.boxType = .custom
		divider.borderType = .noBorder
		divider.fillColor = AppKitColorTokens.fileSearchDivider
		for item in [header, scroll, footer]
		{
			item.translatesAutoresizingMaskIntoConstraints = false
			container.addSubview(item)
		}
		for item in [queryField, maskLabel, maskField, escapeButton]
		{
			item.translatesAutoresizingMaskIntoConstraints = false
			header.addSubview(item)
		}
		for item in [divider, statusLabel, keyboardHints]
		{
			item.translatesAutoresizingMaskIntoConstraints = false
			footer.addSubview(item)
		}
		maskLabel.isHidden = mode == .filename
		maskField.isHidden = mode == .filename
		NSLayoutConstraint.activate([
			header.topAnchor.constraint(equalTo: container.topAnchor),
			header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			header.heightAnchor.constraint(equalToConstant: LayoutTokens.FileSearch.headerHeight),
			scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
			scroll.leadingAnchor.constraint(
				equalTo: container.leadingAnchor,
				constant: LayoutTokens.FileSearch.resultsHorizontalInset
			),
			scroll.trailingAnchor.constraint(
				equalTo: container.trailingAnchor,
				constant: -LayoutTokens.FileSearch.resultsHorizontalInset
			),
			footer.topAnchor.constraint(equalTo: scroll.bottomAnchor),
			footer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			footer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			footer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
			footer.heightAnchor.constraint(equalToConstant: LayoutTokens.FileSearch.footerHeight),
			queryField.leadingAnchor.constraint(
				equalTo: header.leadingAnchor,
				constant: 22
			),
			queryField.centerYAnchor.constraint(equalTo: header.centerYAnchor),
			queryField.heightAnchor.constraint(equalToConstant: 26),
			maskLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
			maskField.centerYAnchor.constraint(equalTo: header.centerYAnchor),
			maskField.widthAnchor.constraint(equalToConstant: 112),
			maskField.heightAnchor.constraint(equalToConstant: 26),
			escapeButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
			escapeButton.trailingAnchor.constraint(
				equalTo: header.trailingAnchor,
				constant: -LayoutTokens.FileSearch.footerHorizontalInset
			),
			divider.topAnchor.constraint(equalTo: footer.topAnchor),
			divider.heightAnchor.constraint(equalToConstant: 1),
			divider.leadingAnchor.constraint(
				equalTo: footer.leadingAnchor,
				constant: LayoutTokens.FileSearch.resultsHorizontalInset
			),
			divider.trailingAnchor.constraint(
				equalTo: footer.trailingAnchor,
				constant: -LayoutTokens.FileSearch.resultsHorizontalInset
			),
			statusLabel.leadingAnchor.constraint(
				equalTo: footer.leadingAnchor,
				constant: LayoutTokens.FileSearch.footerHorizontalInset
			),
			statusLabel.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
			keyboardHints.trailingAnchor.constraint(
				equalTo: footer.trailingAnchor,
				constant: -LayoutTokens.FileSearch.footerHorizontalInset
			),
			keyboardHints.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
			statusLabel.trailingAnchor.constraint(
				lessThanOrEqualTo: keyboardHints.leadingAnchor,
				constant: -8
			),
		])
		if mode == .content
		{
			NSLayoutConstraint.activate([
				queryField.trailingAnchor.constraint(
					equalTo: maskLabel.leadingAnchor,
					constant: -12
				),
				maskLabel.trailingAnchor.constraint(
					equalTo: maskField.leadingAnchor,
					constant: -8
				),
				maskField.trailingAnchor.constraint(
					equalTo: escapeButton.leadingAnchor,
					constant: -8
				),
			])
		}
		else
		{
			queryField.trailingAnchor.constraint(
				equalTo: escapeButton.leadingAnchor,
				constant: -8
			)
			.isActive = true
		}
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	static func preferredSize(in parent: NSWindow) -> NSSize
	{
		NSSize(
			width: min(
				LayoutTokens.FileSearch.preferredWidth,
				max(
					LayoutTokens.FileSearch.minimumWidth,
					parent.frame.width - 2 * LayoutTokens.FileSearch.parentHorizontalInset
				)
			),
			height: LayoutTokens.FileSearch.height
		)
	}

	private func refreshBackground()
	{
		layer?.backgroundColor = AppKitColorResolution.resolvedCGColor(
			.textBackgroundColor,
			for: self
		)
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		refreshBackground()
	}
}
