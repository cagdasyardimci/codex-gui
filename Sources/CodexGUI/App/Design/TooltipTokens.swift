import Foundation

extension LayoutTokens
{
	enum Tooltip
	{
		enum Capsule
		{
			static let maximumWidth: CGFloat = 320
			static let horizontalInset: CGFloat = 13
			static let verticalInset: CGFloat = 6
			static let anchorGap: CGFloat = 2
			static let shadowOutset: CGFloat = 30
		}
	}
}

extension ShapeTokens
{
	enum Tooltip
	{
		static let capsuleRadius: CGFloat = 20
	}
}

extension TypographyTokens
{
	enum Tooltip
	{
		static let control = Role(
			size: 13,
			lineHeight: 18,
			tracking: -0.15
		)
		static let capsule = Role(
			size: 13,
			lineHeight: 17.875,
			tracking: -0.15
		)
	}
}
