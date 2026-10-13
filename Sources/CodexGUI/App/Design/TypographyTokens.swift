import Foundation

/// Value-only typography policy; native fonts are created by AppKitFontResolver on the main actor.
enum TypographyTokens
{
	static let opticalSizeMinimum: CGFloat = 17
	static let interfaceWeight: CGFloat = 430
	static let interfaceStrongWeight: CGFloat = 600

	enum Weight: Sendable
	{
		case regular, medium, semibold, bold
	}
	enum Selection: Sendable
	{
		case interface(weight: CGFloat)
		case system(weight: Weight)
		case monospaced(weight: Weight)
		case menlo(bold: Bool)
	}

	struct Role: Sendable
	{
		let size: CGFloat
		let selection: Selection
		let lineHeight: CGFloat?
		let baselineCorrection: CGFloat
		let tracking: CGFloat?
		let ligatures: Int?

		init(
			size: CGFloat,
			selection: Selection = .interface(weight: TypographyTokens.interfaceWeight),
			lineHeight: CGFloat? = nil,
			baselineCorrection: CGFloat = 0,
			tracking: CGFloat? = nil,
			ligatures: Int? = nil
		)
		{
			self.size = size
			self.selection = selection
			self.lineHeight = lineHeight
			self.baselineCorrection = baselineCorrection
			self.tracking = tracking
			self.ligatures = ligatures
		}

		func emphasized(_ bold: Bool) -> Role
		{
			guard bold
			else
			{
				return self
			}
			let emphasizedSelection: Selection
			switch selection
			{
			case .interface: emphasizedSelection = .interface(weight: interfaceStrongWeight)
			case .system(weight: .bold): emphasizedSelection = selection
			case .system: emphasizedSelection = .system(weight: .semibold)
			case .monospaced(weight: .bold): emphasizedSelection = selection
			case .monospaced: emphasizedSelection = .monospaced(weight: .semibold)
			case .menlo: emphasizedSelection = .menlo(bold: true)
			}
			return Role(
				size: size,
				selection: emphasizedSelection,
				lineHeight: lineHeight,
				baselineCorrection: baselineCorrection,
				tracking: tracking,
				ligatures: ligatures
			)
		}
	}

	enum Sidebar
	{
		static let row = Role(size: 14)
		static let section = Role(
			size: 14,
			selection: .interface(weight: 500)
		)
	}

	enum Composer
	{
		static let editor = Role(
			size: 14,
			lineHeight: 20,
			baselineCorrection: 2,
			ligatures: 0
		)
		static let preference = Role(
			size: 13,
			selection: .interface(weight: 400)
		)
		static let contextMenu = Role(size: 13)
		static let warning = Role(
			size: 12,
			selection: .system(weight: .regular)
		)
		static let plan = Role(
			size: 12,
			selection: .system(weight: .medium)
		)
	}

	enum Transcript
	{
		static let prose = Role(
			size: 14,
			selection: .system(weight: .regular)
		)
		static let code = Role(
			size: 13,
			selection: .monospaced(weight: .regular)
		)
		static let codeHeader = Role(
			size: 11,
			selection: .monospaced(weight: .regular)
		)
		static let inlineCode = Role(
			size: 13,
			selection: .monospaced(weight: .medium)
		)
		static let table = Role(
			size: 12.25,
			lineHeight: 22.75
		)
		static let tableHeader = Role(
			size: 12.25,
			selection: .interface(weight: TypographyTokens
				.interfaceStrongWeight),
			lineHeight: 14
		)
		static let minorHeadingSize: CGFloat = 14
		static let thematicBreakLineHeight: CGFloat = 16
		static let title = Role(
			size: 12,
			selection: .system(weight: .medium)
		)
		static let listMarker = Role(
			size: 14,
			selection: .system(weight: .bold)
		)
		static let codeLanguage = Role(
			size: 12,
			selection: .system(weight: .medium)
		)
		static func headingSize(level: Int) -> CGFloat
		{
			switch level
			{
			case 1: 24
			case 2: 20
			case 3: 18
			case 4: 16
			default: minorHeadingSize
			}
		}

		static func heading(level: Int) -> Role
		{
			Role(
				size: headingSize(level: level),
				selection: .system(weight: .bold)
			)
		}
	}

	enum Controls
	{
		static let button = Role(
			size: 12,
			selection: .system(weight: .regular)
		)
		static let prominentButton = Role(
			size: 12,
			selection: .system(weight: .medium)
		)
		static let section = Role(
			size: 11,
			selection: .system(weight: .medium)
		)
		static let title = Role(
			size: 17,
			selection: .system(weight: .bold)
		)
		static let tab = Role(
			size: 13,
			selection: .system(weight: .regular)
		)
	}

	enum Popover
	{
		static let title = Role(size: 13)
		static let explanation = Role(size: 12)
	}

	enum ModelPopover
	{
		static let effort = Role(
			size: 14,
			selection: .interface(weight: 500)
		)
		static let model = Role(
			size: 12,
			selection: .interface(weight: 400)
		)
		static let availability = Role(
			size: 11,
			selection: .system(weight: .regular)
		)
		static let menuLineHeight: CGFloat = 18.5703125
		static let modelExplanationLineHeight: CGFloat = 16
		static let menu = Role(
			size: 13,
			lineHeight: menuLineHeight
		)
		static let modelExplanation = Role(
			size: 12,
			lineHeight: modelExplanationLineHeight
		)
	}

	enum Summary
	{
		static let body = Role(
			size: 13,
			selection: .system(weight: .regular)
		)
		static let status = Role(
			size: 11,
			selection: .system(weight: .regular)
		)
	}

	enum Toolbar
	{
		static let title = Role(
			size: 14,
			selection: .system(weight: .regular)
		)

	}

	enum TaskHover
	{
		static let title = Role(
			size: 14,
			selection: .interface(weight: 500),
			lineHeight: 20
		)
		static let project = Role(
			size: 13,
			lineHeight: 20
		)
		static let metadata = Role(
			size: 12,
			lineHeight: 20
		)
	}
}
