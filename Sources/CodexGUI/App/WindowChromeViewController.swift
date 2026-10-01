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
		let panel = RoundedContentPanel()
		for child in [column, panel]
		{
			child.translatesAutoresizingMaskIntoConstraints = false
			view.addSubview(child)
		}
		split.view.translatesAutoresizingMaskIntoConstraints = false
		panel.addSubview(split.view)
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
			panel.leadingAnchor.constraint(equalTo: column.trailingAnchor),
			panel.trailingAnchor.constraint(
				equalTo: view.trailingAnchor,
				constant: -4
			),
			panel.topAnchor.constraint(equalTo: view.topAnchor),
			panel.bottomAnchor.constraint(
				equalTo: view.bottomAnchor,
				constant: -4
			),
			split.view.leadingAnchor.constraint(
				equalTo: panel.leadingAnchor,
				constant: 1
			),
			split.view.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
			split.view.topAnchor.constraint(equalTo: panel.topAnchor),
			split.view.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
		])
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}

/// Clips workspace content and draws its rounded border inside the window chrome.
@MainActor
private final class RoundedContentPanel: NSView
{
	// The inner curve accounts for the 4-point inset from the window corner.
	private let cornerRadius: CGFloat = 16

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.cornerRadius = cornerRadius
		layer?.cornerCurve = .continuous
		layer?.borderWidth = 1
		layer?.masksToBounds = true
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func layout()
	{
		super.layout()
		let radius = min(
			cornerRadius,
			bounds.height / 2,
			bounds.width
		)
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		layer?.cornerRadius = radius
		layer?.borderColor = DesktopTheme.border.cgColor
		CATransaction.commit()
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsLayout = true
	}
}
