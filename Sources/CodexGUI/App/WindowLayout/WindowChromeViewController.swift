import AppKit

/// Keeps the account column visible independently of the collapsible workspace panes.
@MainActor
final class WindowChromeViewController: NSViewController
{
	private typealias Layout = LayoutTokens.Chrome

	private var accountColumn: NSView!
	private var panel: RoundedContentPanel!
	private var panelShadow: RoundedContentShadow!
	private var accountWidth: NSLayoutConstraint!
	private var trailingInset: NSLayoutConstraint!
	private var bottomInset: NSLayoutConstraint!
	private var topInset: NSLayoutConstraint!
	private var splitInset: NSLayoutConstraint!

	func setGitReviewFocused(_ focused: Bool)
	{
		accountColumn.isHidden = focused
		accountWidth.constant = focused ? 0 : Layout.accountColumnWidth
		trailingInset.constant = focused ? 0 : -Layout.panelOuterInset
		bottomInset.constant = focused ? 0 : -Layout.panelOuterInset
		topInset.constant = focused ? 0 : Layout.panelTopInset
		splitInset.constant = focused ? 0 : Layout.splitLeadingInset
		panel.isGitReviewFocused = focused
		panelShadow.isHidden = focused
		view.needsLayout = true
	}

	init(
		split: NSSplitViewController,
		accountButton: NSButton
	)
	{
		super.init(
			nibName: nil,
			bundle: nil
		)
		view = DesktopSurface(AppKitColorTokens.chrome)
		addChild(split)

		let column = DesktopSurface(AppKitColorTokens.chrome)
		let avatar = DesktopSurface(
			AppKitColorTokens.selection,
			cornerRadius: Layout.avatarSize / 2
		)
		let panel = RoundedContentPanel()
		let shadow = RoundedContentShadow()
		self.accountColumn = column
		self.panel = panel
		self.panelShadow = shadow
		accountWidth = column.widthAnchor.constraint(equalToConstant: Layout.accountColumnWidth)
		trailingInset = panel.trailingAnchor.constraint(
			equalTo: view.trailingAnchor,
			constant: -Layout.panelOuterInset
		)
		bottomInset = panel.bottomAnchor.constraint(
			equalTo: view.bottomAnchor,
			constant: -Layout.panelOuterInset
		)
		topInset = panel.topAnchor.constraint(
			equalTo: view.topAnchor,
			constant: Layout.panelTopInset
		)
		splitInset = split.view.leadingAnchor.constraint(
			equalTo: panel.leadingAnchor,
			constant: Layout.splitLeadingInset
		)
		for child in [column, shadow, panel]
		{
			child.translatesAutoresizingMaskIntoConstraints = false
			view.addSubview(child)
		}
		split.view.translatesAutoresizingMaskIntoConstraints = false
		panel.addSubview(split.view)
		avatar.translatesAutoresizingMaskIntoConstraints = false
		accountButton.translatesAutoresizingMaskIntoConstraints = false
		column.addSubview(avatar)
		column.addSubview(accountButton)

		NSLayoutConstraint.activate([
			column.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			column.topAnchor.constraint(equalTo: view.topAnchor),
			column.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			accountWidth,
			avatar.centerXAnchor.constraint(equalTo: column.centerXAnchor),
			accountButton.bottomAnchor.constraint(
				equalTo: column.bottomAnchor,
				constant: -Layout.accountBottomInset
			),
			avatar.widthAnchor.constraint(equalToConstant: Layout.avatarSize),
			avatar.heightAnchor.constraint(equalToConstant: Layout.avatarSize),
			accountButton.centerXAnchor.constraint(equalTo: avatar.centerXAnchor),
			accountButton.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
			panel.leadingAnchor.constraint(equalTo: column.trailingAnchor),
			trailingInset,
			topInset,
			bottomInset,
			shadow.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
			shadow.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
			shadow.topAnchor.constraint(equalTo: panel.topAnchor),
			shadow.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
			splitInset,
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

@MainActor
private final class RoundedContentShadow: NSView
{
	private let cornerRadius = ShapeTokens.NativeChrome.panelRadius

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.cornerCurve = .circular
		layer?.shadowColor = NSColor.black.cgColor
		layer?.shadowOffset = .zero
		layer?.shadowRadius = 8
		updateAppearance()
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
		layer?.shadowPath = CGPath(
			roundedRect: bounds,
			cornerWidth: radius,
			cornerHeight: radius,
			transform: nil
		)
		CATransaction.commit()
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		updateAppearance()
	}

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		updateAppearance()
	}

	private func updateAppearance()
	{
		let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
		layer?.backgroundColor = AppKitColorResolution.resolvedCGColor(
			AppKitColorTokens.chrome,
			for: self
		)
		layer?.shadowOpacity = isDark ? 0 : 0.08
	}
}

/// Clips workspace content and draws its rounded border inside the window chrome.
@MainActor
private final class RoundedContentPanel: NSView
{
	// Match the reference content panel independently of the native window corner.
	private let cornerRadius = ShapeTokens.NativeChrome.panelRadius
	var isGitReviewFocused = false
	{
		didSet
		{
			needsLayout = true
		}
	}

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.cornerRadius = cornerRadius
		layer?.cornerCurve = .circular
		layer?.borderWidth = 0.5
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
		layer?.cornerRadius = isGitReviewFocused ? 0 : radius
		layer?.borderWidth = isGitReviewFocused ? 0 : 0.5
		layer?.borderColor = AppKitColorResolution.resolvedCGColor(
			AppKitColorTokens.border,
			for: self
		)
		CATransaction.commit()
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsLayout = true
	}
}
