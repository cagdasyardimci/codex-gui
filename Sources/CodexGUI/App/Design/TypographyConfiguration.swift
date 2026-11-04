import Foundation

/// Independent user inputs; roles derive their sizes without mutating the catalogue.
struct TypographyConfiguration: Equatable, Hashable, Sendable
{
	static let standard = TypographyConfiguration()
	let uiSize: CGFloat
	let contentSize: CGFloat
	let codeSize: CGFloat

	init(
		uiSize: CGFloat = 14,
		contentSize: CGFloat = 15,
		codeSize: CGFloat = 12
	)
	{
		self.uiSize = uiSize.isFinite ? min(
			16,
			max(
				11,
				uiSize.rounded()
			)
		) : 14
		self.contentSize = contentSize.isFinite ? min(
			24,
			max(
				12,
				contentSize.rounded()
			)
		) : 15
		self.codeSize = codeSize.isFinite ? min(
			24,
			max(
				8,
				codeSize.rounded()
			)
		) : 12
	}

	static var current: Self
	{
		TypographyPreferences().configuration
	}

	func heading(_ referenceSize: CGFloat) -> CGFloat
	{
		(referenceSize * uiSize / 14).rounded()
	}

	func contentHeading(_ referenceSize: CGFloat) -> CGFloat
	{
		(referenceSize * contentSize / 15).rounded()
	}
}
