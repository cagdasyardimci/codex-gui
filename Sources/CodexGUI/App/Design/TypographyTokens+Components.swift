import Foundation

extension TypographyTokens.UI
{
	static let metadata = TypographyTokens.Text.metadata
	static let editor = TypographyTokens.Text.detail
}

extension TypographyTokens.AccountMenu
{
	// Initials are artwork inside an 18-point avatar; scaling them breaks the icon's fit.
	static let avatar = TypographyTokens.Role(rule: .fixed(7))
	static let toolbarInitials = TypographyTokens.Role(size: 10)
}

extension TypographyTokens.Controls
{
	static let panelTitle = TypographyTokens.Role(
		size: 15,
		selection: .interface(weight: .strong)
	)
	static let panelHeading = TypographyTokens.Role(
		size: 15,
		selection: .interface(weight: .medium)
	)
	static let smallPopup = TypographyTokens.Role(
		size: 11,
		selection: .interface(weight: .regular)
	)

	static func inline(prominent: Bool) -> TypographyTokens.Role
	{
		prominent ? TypographyTokens.Text.smallLabel : TypographyTokens.Text.secondary
	}

	static func disclosure(compact: Bool) -> TypographyTokens.Role
	{
		compact ? TypographyTokens.UI.small : TypographyTokens.UI.body
	}
}

extension TypographyTokens.Toolbar
{
	static let control = TypographyTokens.Text.detail
}

extension TypographyTokens.Sidebar
{
	static let placeholder = TypographyTokens.Role(
		size: 14,
		selection: .interface(weight: .regular)
	)
	static let workspacePicker = TypographyTokens.Text.metadata
}

extension TypographyTokens.Dialog
{
	static let body = TypographyTokens.Role(
		size: 14,
		lineSpacing: 3
	)
	static let section = TypographyTokens.Text.section
	static let message = TypographyTokens.Text.paragraph
}

extension TypographyTokens.Composer
{
	static func queue(preview: Bool) -> TypographyTokens.Role
	{
		TypographyTokens.Role(
			size: preview ? 14 : 13,
			lineHeight: preview ? 20 : 18
		)
	}
}

extension TypographyTokens.Connections
{
	static let pairingCode = TypographyTokens.Role(
		size: 36,
		selection: .interface(weight: .strong),
		tracking: 6.48
	)
}

extension TypographyTokens.Settings
{
	static let formDescription = TypographyTokens.Text.secondary
	static let formInput = TypographyTokens.Text.input
	static let tableColumn = TypographyTokens.Text.label

	static func tableCell(header: Bool) -> TypographyTokens.Role
	{
		header ? TypographyTokens.Text.secondary : TypographyTokens.Text.label
	}
}

extension TypographyTokens.Search
{
	static let explanation = TypographyTokens.Text.caption
	static let resultTitle = TypographyTokens.Text.paragraph
	static let resultDetail = TypographyTokens.Text.detail
	static let resultSection = TypographyTokens.Text.caption
	static let filename = resultTitle
	static let filenameDetail = resultDetail
	static let commandTitle = TypographyTokens.Text.label
	static let commandDetail = TypographyTokens.Text.metadata
	static let messageTitle = TypographyTokens.Text.smallLabel
	static let messageSnippet = TypographyTokens.Text.caption

	static func input(overlay: Bool) -> TypographyTokens.Role
	{
		overlay ? TypographyTokens.Text.body : TypographyTokens.Text.detail
	}
}

extension TypographyTokens
{
	enum Files
	{
		static let path = TypographyTokens.Text.body
		static let location = Role(size: 15)
		static let treeRow = TypographyTokens.Text.detail
		static let metadataHeading = TypographyTokens.Text.caption

		static func breadcrumb(current: Bool) -> Role
		{
			current ? TypographyTokens.Text.label : TypographyTokens.Text.detail
		}
	}

	enum Changes
	{
		static let description = Role(
			size: 12,
			lineSpacing: 3
		)
		static let reviewAction = TypographyTokens.Text.metadata
		static let fileReview = TypographyTokens.Text.detail
		static let statistics = TypographyTokens.Text.detail
		static let fileHeading = TypographyTokens.Text.title
	}

	enum Interaction
	{
		static let title = TypographyTokens.Text.section
		static let detail = TypographyTokens.Text.caption
		static let question = TypographyTokens.Text.detail
	}

	enum Sources
	{
		static let title = TypographyTokens.Text.title
		static let metadata = TypographyTokens.Text.detail
		static let provider = TypographyTokens.Text.rowLabel
		static let previewTitle = TypographyTokens.Text.label
	}

	enum Subagents
	{
		static let section = TypographyTokens.Text.detail
		static let timing = TypographyTokens.Text.caption
		static let name = TypographyTokens.Text.detail
	}

	enum Resource
	{
		static let detail = TypographyTokens.Text.caption

		static func title(attachment: Bool) -> Role
		{
			attachment ? TypographyTokens.Text.label : TypographyTokens.Text.detail
		}
	}

	enum Activity
	{
		static let title = TypographyTokens.Text.body
		static let outcome = TypographyTokens.Text.caption
	}

	enum Status
	{
		enum Presentation
		{
			case compact, inline, regular
		}

		static func title(presentation: Presentation) -> Role
		{
			Role(
				size: presentation == .compact ? 11 : presentation == .inline ? 12 : 16,
				selection: .interface(weight: .medium)
			)
		}

		static func message(presentation: Presentation) -> Role
		{
			switch presentation
			{
			case .compact: TypographyTokens.Text.metadata
			case .inline: TypographyTokens.Text.caption
			case .regular: TypographyTokens.Text.detail
			}
		}
	}

	enum Math
	{
		// KaTeX owns mathematical faces and layout; this role supplies source fallback metrics.
		static let display = Role(
			rule: .fixed(20),
			selection: .system(weight: .regular)
		)

		static func inline(size: CGFloat) -> Role
		{
			Role(
				rule: .fixed(size),
				selection: .system(weight: .regular)
			)
		}
	}

	enum Diagram
	{
		static let body = TypographyTokens.Text.body
		static let edge = TypographyTokens.Text.section
		// Flowchart node labels anchor the renderer's measured geometry independently of UI size.
		static let node = Role(
			rule: .fixed(14),
			selection: TypographyTokens.Text.section.selection
		)
	}
}

extension TypographyTokens.TurnPreview
{
	static let reply = TypographyTokens.Role(
		size: 13,
		lineSpacing: 4
	)
}

extension TypographyTokens.Terminal
{
	static let status = TypographyTokens.Text.detail
}

extension TypographyTokens.Code
{
	static let fallback = TypographyTokens.Role(
		rule: .code,
		selection: .code(weight: .text),
		lineSpacing: 2
	)
}

extension TypographyTokens.Transcript
{
	static func inlineCode(
		in parent: TypographyTokens.Role,
		strong: Bool
	) -> TypographyTokens.Role
	{
		TypographyTokens.Role(
			rule: .scaled(
				parent.sizeRule,
				inlineCodeScale
			),
			selection: .code(weight: parent.emphasized(strong).weight),
			lineHeight: parent.lineHeightRule
		)
	}
}

extension TypographyTokens.FileMarkdown
{
	static let codeLanguage = TypographyTokens.Text.caption

	static func inlineCode(
		heading: Bool,
		strong: Bool
	) -> TypographyTokens.Role
	{
		TypographyTokens.Role(
			rule: inlineCode.sizeRule,
			selection: .code(weight: heading ? .medium : strong ? .strong :
				.text)
		)
	}
}
