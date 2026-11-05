import AppKit

/// A form disclosure owns expansion, card spacing and its section header.
@MainActor
final class SettingsDisclosureSection: NSView
{
	private let button: DesktopDisclosureButton
	private let content: NSStackView
	private var expanded = true

	init(
		title: String,
		cards: [NSView]
	)
	{
		button = DesktopDisclosureButton(
			title: title,
			expanded: true
		)
		content = AppKitLayout.verticalStack(
			cards,
			spacing: LayoutTokens.Settings.formCardGap
		)
		super.init(frame: .zero)
		button.target = self
		button.action = #selector(toggle)
		let header = NSView()
		button.translatesAutoresizingMaskIntoConstraints = false
		header.addSubview(button)
		NSLayoutConstraint.activate([
			header.heightAnchor.constraint(equalToConstant: 70),
			button.leadingAnchor.constraint(equalTo: header.leadingAnchor),
			button.bottomAnchor.constraint(
				equalTo: header.bottomAnchor,
				constant: -16
			),
		])
		let stack = AppKitLayout.verticalStack(
			[header, content],
			spacing: 0
		)
		AppKitLayout.pin(
			stack,
			to: self,
			inset: 0
		)
		for view in [header, content]
		{
			view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		for card in cards
		{
			card.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
		}
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	@objc private func toggle()
	{
		expanded.toggle()
		button.setExpanded(expanded)
		content.isHidden = !expanded
	}
}
