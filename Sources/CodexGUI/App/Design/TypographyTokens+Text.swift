import Foundation

extension TypographyTokens
{
	/// Reusable text configurations. Feature roles alias these when their presentation
	/// contract matches; renderer metrics and constrained artwork keep their own rules.
	enum Text
	{
		static let body = Role(size: 14)
		static let detail = Role(size: 13)
		static let caption = Role(size: 12)
		static let metadata = Role(size: 11)
		static let paragraph = Role(
			rule: body.sizeRule,
			lineHeight: .multiple(1.5)
		)
		static let title = Role(
			size: 14,
			selection: .interface(weight: .medium)
		)
		static let label = Role(
			size: 13,
			selection: .interface(weight: .medium)
		)
		static let smallLabel = Role(
			size: 12,
			selection: .interface(weight: .medium)
		)
		static let section = Role(
			size: 13,
			selection: .interface(weight: .strong)
		)
		static let input = Role(
			size: 13,
			selection: .interface(weight: .regular)
		)
		static let secondary = Role(
			size: 12,
			selection: .interface(weight: .regular)
		)
		static let menu = Role(
			rule: .ui(offset: -1),
			lineHeight: .multiple(10.0 / 7)
		)
		static let menuSupport = Role(
			rule: caption.sizeRule,
			lineHeight: .multiple(7.0 / 6)
		)

		static func button(compact: Bool) -> Role
		{
			Role(
				rule: compact ? detail.sizeRule : body.sizeRule,
				selection: .interface(weight: .regular),
				lineHeight: .multiple(1)
			)
		}

		// Dialog actions retain UI emphasis and their own action line box.
		static let action = Role(
			rule: body.sizeRule,
			lineHeight: .fixed(18)
		)

		static func heading(
			_ size: CGFloat,
			weight: TypographyTokens.Weight = .strong
		) -> Role
		{
			Role(
				rule: .heading(size),
				selection: .interface(weight: weight),
				lineHeight: .multiple(1.4)
			)
		}

		// Composer labels share input emphasis while retaining the footer's line box.
		static let composerControl = Role(
			rule: input.sizeRule,
			selection: input.selection,
			lineHeight: .fixed(18)
		)
		// Intrinsic text, menu rows and fixed-height controls have different line-box contracts.
		static let control = Role(
			size: 14,
			lineHeight: 20
		)
		static let compactControl = Role(
			size: 13,
			lineHeight: 18.5714
		)
		static let controlLabel = Role(
			size: 14,
			selection: .interface(weight: .medium),
			lineHeight: 20
		)
		static let rowLabel = Role(
			rule: menu.sizeRule,
			selection: label.selection,
			lineHeight: menu.lineHeightRule
		)
		static let captionLine = Role(
			size: 12,
			lineHeight: 16
		)
	}
}
