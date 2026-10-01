import AppKit

/// Keeps the account column visible independently of the collapsible workspace panes.
@MainActor
final class WindowChromeViewController: NSViewController
{
	init(
		split: NSSplitViewController,
		accountButton: NSButton
	)
	{
		super.init(
			nibName: nil,
			bundle: nil
		)
		view = DesktopSurface(DesktopTheme.chrome)
		addChild(split)

		let column = DesktopSurface(DesktopTheme.chrome)
		let avatar = DesktopSurface(
			DesktopTheme.selection,
			cornerRadius: 16
		)
		let divider = DesktopSurface(DesktopTheme.border)
		for child in [column, split.view, divider]
		{
			child.translatesAutoresizingMaskIntoConstraints = false
			view.addSubview(child)
		}
		avatar.translatesAutoresizingMaskIntoConstraints = false
		accountButton.translatesAutoresizingMaskIntoConstraints = false
		column.addSubview(avatar)
		avatar.addSubview(accountButton)

		NSLayoutConstraint.activate([
			column.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			column.topAnchor.constraint(equalTo: view.topAnchor),
			column.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			column.widthAnchor.constraint(equalToConstant: 52),
			avatar.centerXAnchor.constraint(equalTo: column.centerXAnchor),
			avatar.bottomAnchor.constraint(
				equalTo: column.bottomAnchor,
				constant: -12
			),
			avatar.widthAnchor.constraint(equalToConstant: 32),
			avatar.heightAnchor.constraint(equalToConstant: 32),
			accountButton.centerXAnchor.constraint(equalTo: avatar.centerXAnchor),
			accountButton.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
			divider.leadingAnchor.constraint(equalTo: column.trailingAnchor),
			divider.topAnchor.constraint(equalTo: view.topAnchor),
			divider.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			divider.widthAnchor.constraint(equalToConstant: 1),
			split.view.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
			split.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			split.view.topAnchor.constraint(equalTo: view.topAnchor),
			split.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
		])
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
