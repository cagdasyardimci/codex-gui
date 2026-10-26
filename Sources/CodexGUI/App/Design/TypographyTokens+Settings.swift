import Foundation

extension TypographyTokens
{
	enum Settings
	{
		static let search = Role(
			size: 14,
			selection: .interface(weight: 430),
			lineHeight: 18
		)
		static let sidebarRow = Role(
			size: 14,
			selection: .interface(weight: 400),
			lineHeight: 21
		)
		static let heading = Role(
			size: 18,
			selection: .interface(weight: 600),
			lineHeight: 24
		)
		static let section = Role(
			size: 14,
			selection: .interface(weight: 500),
			lineHeight: 21
		)
	}
}
