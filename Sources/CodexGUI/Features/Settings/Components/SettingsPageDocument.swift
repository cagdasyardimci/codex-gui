import AppKit

/// A complete settings page owns its header, section rhythm and reading-column scroll shell.
@MainActor
final class SettingsPageDocument: NSView
{
	enum HeaderSpacing
	{
		case standard, catalog
	}

	private let stack: NSStackView

	convenience init(
		title: String,
		sections: [NSView],
		headerAccessory: NSView? = nil,
		subtitle: String? = nil,
		subtitleView: NSView? = nil,
		headerSpacing: HeaderSpacing = .standard,
		columnWidth: SettingsPageLayout.ColumnWidth = .fixed
	)
	{
		let heading = DesktopLineBoxLabel(
			title,
			role: TypographyTokens.Connections.title
		)
		let headingContent: NSView
		if let detail = subtitleView ?? subtitle.map(
			{
				SettingsPageLayout.message($0)
			}
		)
		{
			headingContent = AppKitLayout.verticalStack(
				[heading, detail],
				spacing: 4
			)
		}
		else
		{
			headingContent = heading
		}
		let header: NSView
		if let headerAccessory
		{
			let row = NSStackView(views: [headingContent, NSView(), headerAccessory])
			row.orientation = .horizontal
			row.spacing = 12
			header = row
		}
		else
		{
			header = headingContent
		}
		self.init(
			header: header,
			sections: sections,
			sectionGap: LayoutTokens.Connections.sectionGap,
			titleGap: Self.titleGap(for: headerSpacing),
			columnWidth: columnWidth
		)
	}

	private static func titleGap(for spacing: HeaderSpacing) -> CGFloat
	{
		switch spacing
		{
		case .standard: LayoutTokens.Connections.titleTabGap
		case .catalog: LayoutTokens.Settings.pluginsTitleTabGap
		}
	}

	convenience init(
		accountSectionTitle: String,
		rows: [NSView]
	)
	{
		let title = DesktopLineBoxLabel(
			"Account",
			role: TypographyTokens.Connections.title
		)
		let section = DesktopLineBoxLabel(
			accountSectionTitle,
			role: TypographyTokens.Connections.section
		)
		let header = AppKitLayout.verticalStack(
			[title, section],
			spacing: 46
		)
		self.init(
			header: header,
			sections: [SettingsPageLayout.card(rows: rows)],
			sectionGap: 16,
			titleGap: 16,
			columnWidth: .fitsViewport
		)
	}

	private init(
		header: NSView,
		sections: [NSView],
		sectionGap: CGFloat,
		titleGap: CGFloat,
		columnWidth: SettingsPageLayout.ColumnWidth
	)
	{
		stack = AppKitLayout.verticalStack(
			[header],
			spacing: sectionGap
		)
		super.init(frame: .zero)
		stack.setCustomSpacing(
			titleGap,
			after: header
		)
		header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		for section in sections
		{
			appendSection(section)
		}
		AppKitLayout.pin(
			SettingsPageLayout.scrollableDocument(
				content: stack,
				columnWidth: columnWidth
			),
			to: self,
			inset: 0
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func appendSection(_ section: NSView)
	{
		stack.addArrangedSubview(section)
		section.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
	}
}
