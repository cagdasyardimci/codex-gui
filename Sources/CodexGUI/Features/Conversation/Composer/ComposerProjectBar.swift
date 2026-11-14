import AppKit

/// Project context above the composer; device eligibility stays with the caller.
@MainActor
final class ComposerProjectBar: DesktopSurface
{
	let computerButton = DesktopStyledButton(
		title: "This computer",
		presentation: .contextSelection,
		size: .regular
	)
	let projectSelector = DesktopClearableSelector()
	var projectButton: DesktopStyledButton
	{
		projectSelector.button
	}
	var onClearProject: (() -> Void)?

	var onChooseProject: (() -> Void)?

	init()
	{
		super.init(
			AppKitColorTokens.composerContext,
			cornerRadius: 20,
			roundedCorners: [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
		)
		computerButton.image = DesktopIcons.localComputerImage()
		computerButton.state = .on
		computerButton.isEnabled = false
		projectSelector.onClear =
		{
			[weak self] in self?.onClearProject?()
		}
		projectButton.target = self
		projectButton.action = #selector(chooseProject)
		projectButton.toolTip = "Select a project to run your chat in"
		projectButton.tooltipShortcut = "⌥⇧⌘O"
		let row = AppKitLayout.horizontalStack(
			[computerButton, projectSelector, NSView()],
			spacing: 8
		)
		AppKitLayout.pin(
			row,
			to: self,
			insets: NSEdgeInsets(
				top: 6,
				left: 7,
				bottom: 10,
				right: 7
			)
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	@objc private func chooseProject()
	{
		onChooseProject?()
	}
}
