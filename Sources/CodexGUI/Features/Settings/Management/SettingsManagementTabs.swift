import AppKit

/// Compact tabs keep selection separate from transient hover and keyboard focus.
@MainActor
final class SettingsManagementTabs: NSStackView
{
	private var buttons: [(title: String, button: DesktopStyledButton)] = []

	init(
		titles: [String],
		selected: String,
		counts: [String: Int] = [:],
		onSelect: @escaping (String) -> Void
	)
	{
		super.init(frame: .zero)
		orientation = .horizontal
		spacing = 4
		for title in titles
		{
			let displayTitle = counts[title].map
			{
				"\(title)  \($0)"
			} ?? title
			let button = DesktopActionButton(
				title: displayTitle,
				presentation: .tab(selected: title == selected)
			)
			{
				onSelect(title)
			}
			buttons.append((title, button))
			button.setAccessibilityLabel(displayTitle)
			addArrangedSubview(button)
		}
		select(title: selected)
	}
	func select(title: String)
	{
		for (id, button) in buttons
		{
			button.presentation = .tab(selected: id == title)
			button.setAccessibilityValue(id == title ? "Selected" : "")
		}
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
