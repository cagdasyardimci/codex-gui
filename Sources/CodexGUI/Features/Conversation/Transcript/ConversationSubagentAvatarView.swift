import AppKit

@MainActor
final class ConversationSubagentAvatarView: NSImageView
{
	private let assetName: String

	init(
		assetName: String,
		name: String
	)
	{
		self.assetName = assetName
		super.init(frame: .zero)
		imageScaling = .scaleProportionallyUpOrDown
		toolTip = name
		setAccessibilityLabel(name)
		updateImage()
	}

	@available(
		*,
		unavailable
	)
	required init?(coder: NSCoder)
	{
		fatalError("init(coder:) has not been implemented")
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		updateImage()
	}

	private func updateImage()
	{
		let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
		image = ConversationSubagentAvatars.image(
			named: assetName,
			dark: dark
		)
	}
}
