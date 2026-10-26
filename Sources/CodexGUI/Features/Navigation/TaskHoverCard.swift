import AppKit

/// A passive child window keeps the card beside the row without taking focus.
@MainActor
final class TaskHoverCard
{
	let title: String
	let projectName: String
	let updatedAt: Date?
	private let preview = DesktopHoverPreview()
	var panel: NSPanel?
	{
		preview.panel
	}

	init(
		title: String,
		projectName: String,
		updatedAt: Date?
	)
	{
		self.title = title
		self.projectName = projectName
		self.updatedAt = updatedAt
	}

	func show(beside view: NSView)
	{
		guard panel == nil
		else
		{
			return
		}
		preview.present(
			content: makeCardContent(),
			relativeTo: view,
			placement: .besideTop
		)
	}

	private func makeCardContent() -> NSView
	{
		let titleLabel = NSTextField(wrappingLabelWithString: title)
		titleLabel.font = AppKitFontResolver.font(TypographyTokens.TaskHover.title)
		titleLabel.textColor = AppKitColorTokens.primaryText
		constrainLabel(
			titleLabel,
			toLines: 3,
			role: TypographyTokens.TaskHover.title
		)
		titleLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		let timeLabel = NSTextField(labelWithString: relativeTime())
		timeLabel.font = AppKitFontResolver.font(TypographyTokens.TaskHover.metadata)
		timeLabel.textColor = AppKitColorTokens.secondaryText
		applyLineHeight(
			to: timeLabel,
			role: TypographyTokens.TaskHover.metadata
		)
		let computer = NSImageView(image: NSImage(
			systemSymbolName: "laptopcomputer",
			accessibilityDescription: "This computer"
		) ?? NSImage())
		computer.contentTintColor = .secondaryLabelColor
		let metadata = AppKitLayout.horizontalStack(
			[computer, timeLabel],
			spacing: LayoutTokens.TaskHover.rowSpacing
		)
		let header = AppKitLayout.horizontalStack(
			[titleLabel, NSView(), metadata],
			spacing: LayoutTokens.TaskHover.rowSpacing
		)
		header.alignment = .top
		let folder = NSImageView(image: NSImage(
			systemSymbolName: "folder",
			accessibilityDescription: "Project"
		) ?? NSImage())
		folder.contentTintColor = .secondaryLabelColor
		let projectLabel = NSTextField(wrappingLabelWithString: projectName)
		projectLabel.font = AppKitFontResolver.font(TypographyTokens.TaskHover.project)
		projectLabel.textColor = AppKitColorTokens.primaryText
		constrainLabel(
			projectLabel,
			toLines: 2,
			role: TypographyTokens.TaskHover.project
		)
		let project = AppKitLayout.horizontalStack(
			[folder, projectLabel],
			spacing: LayoutTokens.TaskHover.projectSpacing
		)
		let stack = AppKitLayout.verticalStack(
			[header, project],
			spacing: LayoutTokens.TaskHover.rowSpacing
		)

		header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		project.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		for icon in [computer, folder]
		{
			icon.widthAnchor.constraint(equalToConstant: LayoutTokens.TaskHover.iconSize)
				.isActive = true
			icon.heightAnchor.constraint(equalToConstant: LayoutTokens.TaskHover.iconSize)
				.isActive = true
		}
		timeLabel.setContentCompressionResistancePriority(
			.required,
			for: .horizontal
		)
		return stack
	}

	private func constrainLabel(
		_ label: NSTextField,
		toLines lines: Int,
		role: TypographyTokens.Role
	)
	{
		label.maximumNumberOfLines = lines
		label.lineBreakMode = .byWordWrapping
		label.cell?.truncatesLastVisibleLine = true
		applyLineHeight(
			to: label,
			role: role
		)
		// A natural line-height policy must not turn the multiline cap into two points.
		if let lineHeight = role.lineHeight
		{
			// fittingSize can measure every explicit newline despite the line limit.
			label.heightAnchor
				.constraint(lessThanOrEqualToConstant: lineHeight * CGFloat(lines) + 2)
				.isActive = true
		}
	}

	private func applyLineHeight(
		to label: NSTextField,
		role: TypographyTokens.Role
	)
	{
		let paragraph = NSMutableParagraphStyle()
		paragraph.minimumLineHeight = role.lineHeight ?? 0
		paragraph.maximumLineHeight = role.lineHeight ?? 0
		paragraph.lineBreakMode = label.lineBreakMode
		label.attributedStringValue = NSAttributedString(
			string: label.stringValue,
			attributes: AppKitFontResolver.textAttributes(
				role,
				font: label.font
			).merging(
				[
					.foregroundColor: label.textColor ?? AppKitColorTokens.primaryText,
					.paragraphStyle: paragraph,
				],
				uniquingKeysWith:
				{
					_, replacement in replacement
				}
			)
		)
	}

	func dismiss()
	{
		preview.dismiss()
	}

	private func relativeTime() -> String
	{
		guard let updatedAt
		else
		{
			return ""
		}
		let seconds = max(
			0,
			Int(Date().timeIntervalSince(updatedAt))
		)
		if seconds < 60
		{
			return "now"
		}
		if seconds < 3600
		{
			return "\(seconds / 60)m"
		}
		if seconds < 86400
		{
			return "\(seconds / 3600)h"
		}
		return "\(seconds / 86400)d"
	}
}
