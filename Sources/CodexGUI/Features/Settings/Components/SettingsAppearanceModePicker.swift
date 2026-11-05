import AppKit

/// Mode selection owns its preview artwork and selection; the page supplies profiles and actions.
@MainActor
final class SettingsAppearanceModePicker: NSView
{
	private(set) var selectedMode: ColorThemeMode = .system
	var onSelect: ((ColorThemeMode) -> Void)?
	private(set) var buttons: [NSButton] = []
	private var observation: ThemeColorObservation?

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		buttons = ColorThemeMode.allCases.enumerated().map
		{
			index, mode in
			let button = SettingsAppearanceModeButton(mode: mode)
			button.tag = index
			button.target = self
			button.action = #selector(chooseMode(_:))
			button.setAccessibilityLabel(mode.rawValue.capitalized)
			return button
		}
		let row = AppKitLayout.horizontalStack(
			buttons,
			spacing: LayoutTokens.Settings.modePreviewSpacing
		)
		AppKitLayout.pin(
			row,
			to: self,
			inset: 0
		)
		setAccessibilityLabel("Mode")
		observation = ThemeColorObservation(view: self)
		{
			[weak self] in self?.buttons.forEach
			{
				$0.needsDisplay = true
			}
		}
		select(.system)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func update(configuration: ColorThemeConfiguration)
	{
		for button in buttons.compactMap(
			{
				$0 as? SettingsAppearanceModeButton
			}
		)
		{
			button.configuration = configuration
		}
		select(configuration.mode)
	}

	func select(_ mode: ColorThemeMode)
	{
		selectedMode = mode
		for (button, choice) in zip(
			buttons,
			ColorThemeMode.allCases
		)
		{
			button.state = choice == mode ? .on : .off
			button.needsDisplay = true
		}
	}

	@objc private func chooseMode(_ sender: NSButton)
	{
		guard ColorThemeMode.allCases.indices.contains(sender.tag)
		else
		{
			return
		}
		let mode = ColorThemeMode.allCases[sender.tag]
		select(mode)
		onSelect?(mode)
	}
}

/// Fixed mode illustrations retain semantic accent and selection colors.
@MainActor
private final class SettingsAppearanceModeButton: DesktopHoverButton
{
	private let mode: ColorThemeMode
	var configuration = ColorThemeConfiguration()
	{
		didSet
		{
			needsDisplay = true
		}
	}

	init(mode: ColorThemeMode)
	{
		self.mode = mode
		super.init(frame: .zero)
		setButtonType(.radio)
		isBordered = false
		setAccessibilityRole(.radioButton)
		widthAnchor.constraint(equalToConstant: LayoutTokens.Settings.modePreviewWidth)
			.isActive = true
		heightAnchor.constraint(equalToConstant: LayoutTokens.Settings.modePreviewHeight)
			.isActive = true
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override var alignmentRectInsets: NSEdgeInsets
	{
		NSEdgeInsetsZero
	}

	override func draw(_ dirtyRect: NSRect)
	{
		let outer = NSBezierPath(
			roundedRect: bounds,
			xRadius: 8,
			yRadius: 8
		)
		let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
		let palette = ColorPalette(
			configuration: configuration.profile(for: dark ? .dark : .light),
			mode: dark ? .dark : .light
		)
		NSGraphicsContext.saveGraphicsState()
		outer.addClip()
		for appearance: ColorAppearance in [.light, .dark]
		{
			if mode == .light && appearance == .dark || mode == .dark && appearance == .light
			{
				continue
			}
			NSGraphicsContext.saveGraphicsState()
			if mode == .system
			{
				NSRect(
					x: appearance == .light ? bounds.minX : bounds.midX,
					y: bounds.minY,
					width: bounds.width / 2,
					height: bounds.height
				).clip()
			}
			SettingsAppearanceModeArtwork.draw(
				dark: appearance == .dark,
				accent: palette.accentText,
				in: mode == .system && appearance == .dark ? bounds.offsetBy(
					dx: bounds.width / 2,
					dy: 0
				) : bounds
			)
			NSGraphicsContext.restoreGraphicsState()
		}
		NSGraphicsContext.restoreGraphicsState()
		(state == .on ? AppKitColorTokens.focus : isBackgroundHighlighted ? AppKitColorTokens
			.heavyBorder : AppKitColorTokens.border).setStroke()
		let width: CGFloat = 2
		let outline = NSBezierPath(
			roundedRect: bounds.insetBy(
				dx: width / 2,
				dy: width / 2
			),
			xRadius: 8 - width / 2,
			yRadius: 8 - width / 2
		)
		outline.lineWidth = width
		outline.stroke()
	}
}
