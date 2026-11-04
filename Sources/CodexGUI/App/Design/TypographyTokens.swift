import Foundation

/// Value-only typography policy; native fonts are created by AppKitFontResolver on the main actor.
enum TypographyTokens
{
	static let opticalSizeMinimum: CGFloat = 17
	static let interfaceWeight: Weight = .text
	static let interfaceStrongWeight: Weight = .strong

	enum NativeWeight: Sendable
	{
		case regular, medium, semibold, bold
	}
	/// CSS weight requests remain independent of the faces installed in a family.
	enum Weight: Int, CaseIterable, Sendable
	{
		case regular = 400, text = 430, medium = 500, strong = 600, bold = 700
	}

	enum Selection: Sendable
	{
		case interface(weight: Weight)
		case system(weight: NativeWeight)
		case code(weight: Weight)
		case family(
			String,
			weight: Weight
		)
		case nativeButton
	}

	enum SizeRule: Equatable, Sendable
	{
		case ui(offset: CGFloat)
		case content(offset: CGFloat)
		case heading(CGFloat)
		case contentHeading(CGFloat)
		case code
		case inline(
			scale: CGFloat,
			offset: CGFloat
		)
		case table
		indirect case scaled(
			SizeRule,
			CGFloat
		)
		case fixed(CGFloat)

		func resolve(_ configuration: TypographyConfiguration) -> CGFloat
		{
			switch self
			{
			case let .ui(offset): configuration.uiSize + offset
			case let .content(offset): configuration.contentSize + offset
			case let .heading(reference): configuration.heading(reference)
			case let .contentHeading(reference): configuration.contentHeading(reference)
			case .code: configuration.codeSize
			case let .inline(
				scale,
				offset
			): (configuration.uiSize + offset) * scale
			case .table: max(
					configuration.codeSize,
					configuration.uiSize * 0.875
				)
			case let .scaled(
				rule,
				scale
			): rule.resolve(configuration) * scale
			case let .fixed(value): value
			}
		}
	}

	enum LineHeightRule: Equatable, Sendable
	{
		case fixed(CGFloat)
		case multiple(CGFloat)
		case uiMultiple(CGFloat)
		case source
		case transcriptCode

		func resolve(
			size: CGFloat,
			configuration: TypographyConfiguration
		) -> CGFloat
		{
			switch self
			{
			case let .fixed(value): value
			case let .multiple(value): size * value
			case let .uiMultiple(value): configuration.uiSize * value
			case .source: ceil(size * 1.8)
			case .transcriptCode: max(
					20,
					size * 1.5
				)
			}
		}
	}

	struct Resolved: Sendable
	{
		let size: CGFloat
		let selection: Selection
		let lineHeight: CGFloat?
		let baselineCorrection: CGFloat
		let tracking: CGFloat?
		let ligatures: Int?
		let lineSpacing: CGFloat?
	}

	struct Role: Sendable
	{
		let sizeRule: SizeRule
		var selection: Selection
		let lineHeightRule: LineHeightRule?
		let baselineCorrection: CGFloat
		let tracking: CGFloat?
		let ligatures: Int?
		let lineSpacing: CGFloat?

		var size: CGFloat
		{
			resolved(using: .current).size
		}
		var lineHeight: CGFloat?
		{
			resolved(using: .current).lineHeight
		}

		/// A UI role expressed at the standard 14-point base; headings use an explicit rule.
		init(
			size: CGFloat,
			selection: Selection = .interface(weight: TypographyTokens.interfaceWeight),
			lineHeight: CGFloat? = nil,
			baselineCorrection: CGFloat = 0,
			tracking: CGFloat? = nil,
			ligatures: Int? = nil,
			lineSpacing: CGFloat? = nil
		)
		{
			self.init(
				rule: .ui(offset: size - 14),
				selection: selection,
				lineHeight: lineHeight.map
				{
					.fixed($0)
				},
				baselineCorrection: baselineCorrection,
				tracking: tracking,
				ligatures: ligatures,
				lineSpacing: lineSpacing
			)
		}

		init(
			rule: SizeRule,
			selection: Selection = .interface(weight: TypographyTokens.interfaceWeight),
			lineHeight: LineHeightRule? = nil,
			baselineCorrection: CGFloat = 0,
			tracking: CGFloat? = nil,
			ligatures: Int? = nil,
			lineSpacing: CGFloat? = nil
		)
		{
			sizeRule = rule
			self.selection = selection
			lineHeightRule = lineHeight
			self.baselineCorrection = baselineCorrection
			self.tracking = tracking
			self.ligatures = ligatures
			self.lineSpacing = lineSpacing
		}

		func resolved(using configuration: TypographyConfiguration) -> Resolved
		{
			let size = sizeRule.resolve(configuration)
			return Resolved(
				size: size,
				selection: selection,
				lineHeight: lineHeightRule?.resolve(
					size: size,
					configuration: configuration
				),
				baselineCorrection: baselineCorrection,
				tracking: tracking,
				ligatures: ligatures,
				lineSpacing: lineSpacing
			)
		}

		var weight: Weight
		{
			switch selection
			{
			case let .interface(weight), let .code(weight), let .family(
				_,
				weight
			): weight
			case .system(weight: .medium): .medium
			case .system(weight: .semibold): .strong
			case .system(weight: .bold): .bold
			case .system, .nativeButton: .regular
			}
		}

		func emphasized(_ bold: Bool) -> Role
		{
			guard bold
			else
			{
				return self
			}
			var result = self
			switch selection
			{
			case .interface: result.selection = .interface(weight: .strong)
			case .code(weight: .bold), .system(weight: .bold): break
			case .code: result.selection = .code(weight: .strong)
			case let .family(
				name,
				weight
			):
				result.selection = .family(
					name,
					weight: weight == .bold ? .bold : .strong
				)
			case .nativeButton: result.selection = .system(weight: .semibold)
			case .system: result.selection = .system(weight: .semibold)
			}
			return result
		}
	}

	enum Search
	{
		static let section = TypographyTokens.Text.detail
		static let query = Role(rule: .ui(offset: 2))
		static let shortcut = TypographyTokens.Text.caption
	}

	enum Dialog
	{
		// Dialog headings scale their face inside the shared, fixed heading row.
		static let title = Role(
			rule: TypographyTokens.Text.heading(20).sizeRule,
			selection: TypographyTokens.Text.heading(20).selection,
			lineHeight: .fixed(28)
		)
		static let input = TypographyTokens.Text.menu
		static let action = TypographyTokens.Text.action
	}

	enum TurnPreview
	{
		static let title = TypographyTokens.Text.label
	}

	enum Terminal
	{
		// Terminal follows the configured code family while its size follows the UI base.
		static let text = Role(
			rule: .ui(offset: -1),
			selection: .code(weight: .medium),
			lineHeight: .multiple(1.5)
		)

		static func output(emphasized: Bool) -> Role
		{
			var role = text
			if emphasized
			{
				// ANSI bold requests 700 independently of prose's strong emphasis.
				role.selection = .code(weight: .bold)
			}
			return role
		}
	}

	enum Code
	{
		static let source = Role(
			rule: .code,
			selection: .code(weight: .text),
			lineHeight: .source
		)
		// Diff row geometry uses fractional line spacing; source editors round each line box.
		static let diff = Role(
			rule: .code,
			selection: .code(weight: .text),
			lineHeight: .multiple(1.8)
		)
		static let output = Role(
			rule: .code,
			selection: .code(weight: .text),
			lineHeight: .multiple(1.4)
		)
	}

	enum UI
	{
		static let body = TypographyTokens.Text.body
		static let small = TypographyTokens.Text.menu
		static let caption = TypographyTokens.Text.captionLine
	}

	enum Sidebar
	{
		static let row = TypographyTokens.Text.body
		static let section = TypographyTokens.Text.title
	}

	enum Composer
	{
		static let editor = Role(
			size: 14,
			lineHeight: 20,
			baselineCorrection: 2,
			ligatures: 0
		)
		static let skillMention = TypographyTokens.Text.controlLabel
		static let preference = TypographyTokens.Text.composerControl
		static let contextMenu = TypographyTokens.Text.detail
		static let warning = TypographyTokens.Text.caption
		static let plan = TypographyTokens.Text.detail
	}

	enum ChatLock
	{
		static let title = Role(
			size: 13,
			selection: .interface(weight: interfaceStrongWeight),
			lineHeight: 18.5714
		)
		static let detail = Role(
			size: 13,
			selection: .interface(weight: interfaceWeight),
			lineHeight: 21.125
		)
		static let action = Role(
			size: 13,
			selection: .interface(weight: interfaceWeight),
			lineHeight: 18
		)
	}

	enum FileMarkdown
	{
		static let inlineCode = Role(
			rule: .ui(offset: 0),
			selection: .code(weight: .text)
		)
		static let fencedCode = TypographyTokens.Code.output
		static let mathScale: CGFloat = 1.21
		static let prose = Role(
			rule: .ui(offset: 0),
			lineHeight: .multiple(1.4)
		)

		static func heading(level: Int) -> Role
		{
			let size: CGFloat = switch level
			{
			case 1: 24
			case 2: 20
			case 3: 18
			default: 14
			}
			if level <= 3
			{
				return TypographyTokens.Text.heading(
					size,
					weight: .medium
				)
			}
			return Role(
				rule: .ui(offset: 0),
				selection: .interface(weight: .medium),
				lineHeight: .multiple(1.4)
			)
		}
	}

	enum Transcript
	{
		static let prose = Role(
			rule: .ui(offset: 0),
			selection: .interface(weight: interfaceWeight),
			lineHeight: .multiple(1.625)
		)
		static let code = Role(
			rule: .code,
			selection: .code(weight: .text),
			lineHeight: .transcriptCode
		)
		static let codeHeader = TypographyTokens.Text.label

		static func fileReference(in parent: Role) -> Role
		{
			// Inline file actions reuse label emphasis and inherit the surrounding reading metrics.
			var role = parent
			role.selection = TypographyTokens.Text.title.selection
			return role
		}

		static let inlineCodeScale: CGFloat = 0.92
		static let inlineCode = Role(
			rule: .inline(
				scale: inlineCodeScale,
				offset: 0
			),
			selection: .code(weight: .text)
		)
		static let table = Role(
			rule: .table,
			lineHeight: .uiMultiple(1.625)
		)
		static let tableHeader = Role(
			rule: .table,
			selection: .interface(weight: TypographyTokens
				.interfaceStrongWeight),
			lineHeight: .multiple(1.2)
		)
		static let thematicBreakLineHeight: CGFloat = 16
		static let title = TypographyTokens.Text.smallLabel
		static let listMarker = Role(
			size: 14,
			selection: .interface(weight: .strong)
		)
		static let codeLanguage = TypographyTokens.Text.label
		static func heading(level: Int) -> Role
		{
			// Reading headings scale from prose independently of the application's heading ladder.
			let scale: CGFloat = switch level
			{
			case 1: 1.5
			case 2: 1.25
			case 3: 1.125
			default: 1
			}
			let lineHeight: LineHeightRule? = switch level
			{
			case 1: .uiMultiple(2)
			case 2, 3: .uiMultiple(1.75)
			case 4: .uiMultiple(1.5)
			default: prose.lineHeightRule
			}
			return Role(
				rule: .scaled(
					prose.sizeRule,
					scale
				),
				selection: prose.emphasized(true).selection,
				lineHeight: lineHeight
			)
		}
	}

	enum Controls
	{
		static let button = TypographyTokens.Text.caption
		static let prominentButton = TypographyTokens.Text.caption
		static let section = Role(
			size: 11,
			selection: .interface(weight: .medium)
		)
		static let title = Role(
			rule: .heading(17),
			selection: .interface(weight: .strong)
		)
		static let tab = TypographyTokens.Text.detail
		static let toolsHeading = TypographyTokens.Text.label
		static let toolsTile = TypographyTokens.Text.input
		static let toolsShortcut = TypographyTokens.Text.caption
	}

	enum Popover
	{
		static let title = TypographyTokens.Text.detail
		static let explanation = TypographyTokens.Text.caption
	}

	enum SidebarMenu
	{
		static let lineHeight: CGFloat = 18.5703125
		static let row = TypographyTokens.Text.menu
	}

	enum ModelPopover
	{
		static let effort = TypographyTokens.Text.title
		static let model = TypographyTokens.Text.secondary
		static let availability = TypographyTokens.Text.metadata
		static let menuLineHeight: CGFloat = 18.5703125
		static let modelExplanationLineHeight: CGFloat = 16
		static let menu = TypographyTokens.Text.menu
		static let modelExplanation = Role(
			size: 12,
			lineHeight: modelExplanationLineHeight
		)
	}

	enum FileSearch
	{
		static let source = Role(
			size: 13,
			selection: .code(weight: .text)
		)
		static let location = TypographyTokens.Text.detail
		static let query = Role(size: 15)
		static let accessory = TypographyTokens.Text.detail
		static let maskLabel = TypographyTokens.Text.caption
		static let footer = TypographyTokens.Text.caption
	}

	enum Summary
	{
		static let body = TypographyTokens.Text.detail
		static let status = TypographyTokens.Text.metadata
	}

	enum Toolbar
	{
		static let title = TypographyTokens.Text.title
	}

	enum TaskHover
	{
		static let title = TypographyTokens.Text.controlLabel
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
