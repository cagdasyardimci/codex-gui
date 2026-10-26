import AppKit

/// Catalog entries own artwork, text hierarchy, accessory sizing, and native action controls.
@MainActor
final class SettingsCatalogRow: NSView
{
	struct Action
	{
		let title: String
		var icon: DesktopIcon? = nil
		var enabled = true
		var help: String? = nil
		let activate: () -> Void
	}

	struct Toggle
	{
		let label: String
		let isOn: Bool
		var enabled = true
		var help: String? = nil
		let change: (Bool) -> Void
	}

	enum Accessory
	{
		case action(Action), toggle(Toggle)
	}

	private var toggleActions: [ObjectIdentifier: (Bool) -> Void] = [:]

	init(
		title: String,
		details: [String],
		accessories: [Accessory],
		logoURL: String? = nil
	)
	{
		super.init(frame: .zero)
		let titleLabel = DesktopLineBoxLabel(
			title,
			role: TypographyTokens.Connections.rowLabel
		)
		let detailLabels = details.filter
		{
			!$0.isEmpty
		}.map
		{
			value -> NSTextField in
			let label = SettingsPageLayout.message(value)
			label.maximumNumberOfLines = 1
			label.lineBreakMode = .byTruncatingTail
			return label
		}
		let text = AppKitLayout.verticalStack(
			[titleLabel] + detailLabels,
			spacing: 2
		)
		for label in text.arrangedSubviews
		{
			label.widthAnchor.constraint(equalTo: text.widthAnchor).isActive = true
		}
		let glyph = SettingsCatalogArtwork(logoURL: logoURL)
		let controls = accessories.map(makeAccessory)
		let accessory = AppKitLayout.horizontalStack(
			controls,
			spacing: 8
		)
		let trailing = SettingsRowLayout.accessory(accessory)
		for view in [glyph, text, trailing]
		{
			view.translatesAutoresizingMaskIntoConstraints = false
			addSubview(view)
		}
		NSLayoutConstraint.activate([
			glyph.leadingAnchor.constraint(
				equalTo: leadingAnchor,
				constant: 16
			),
			glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
			glyph.widthAnchor.constraint(equalToConstant: 36),
			glyph.heightAnchor.constraint(equalToConstant: 36),
			text.leadingAnchor.constraint(
				equalTo: glyph.trailingAnchor,
				constant: 12
			),
			text.trailingAnchor.constraint(
				equalTo: trailing.leadingAnchor,
				constant: -16
			),
			text.topAnchor.constraint(
				greaterThanOrEqualTo: topAnchor,
				constant: 9
			),
			text.bottomAnchor.constraint(
				lessThanOrEqualTo: bottomAnchor,
				constant: -9
			),
			text.centerYAnchor.constraint(equalTo: centerYAnchor),
			trailing.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -LayoutTokens.Settings.pluginAccessoryTrailingInset
			),
			trailing.centerYAnchor.constraint(equalTo: centerYAnchor),
			heightAnchor
				.constraint(greaterThanOrEqualToConstant: LayoutTokens.Settings.pluginRowHeight),
		])
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	private func makeAccessory(_ accessory: Accessory) -> NSView
	{
		switch accessory
		{
		case let .action(action):
			let button: DesktopActionButton
			if let icon = action.icon
			{
				button = DesktopActionButton(
					icon: icon,
					label: action.title,
					action: action.activate
				)
			}
			else
			{
				button = DesktopActionButton(
					title: action.title,
					presentation: .secondary,
					action: action.activate
				)
			}
			button.isEnabled = action.enabled
			button.toolTip = action.help
			return button
		case let .toggle(toggle):
			let control = DesktopSwitch()
			control.state = toggle.isOn ? .on : .off
			control.isEnabled = toggle.enabled
			control.toolTip = toggle.help
			control.setAccessibilityLabel(toggle.label)
			control.target = self
			control.action = #selector(toggleChanged(_:))
			toggleActions[ObjectIdentifier(control)] = toggle.change
			return control
		}
	}

	@objc private func toggleChanged(_ control: DesktopSwitch)
	{
		let value = control.state == .on
		control.state = value ? .off : .on
		toggleActions[ObjectIdentifier(control)]?(value)
	}
}

@MainActor
private final class SettingsCatalogArtwork: DesktopSurface
{
	private static let cache = NSCache<NSString, NSImage>()
	private var logo: NSImage?
	private var loadTask: Task<Void, Never>?

	init(logoURL: String?)
	{
		super.init(
			AppKitColorTokens.settingsSelectorSurface,
			cornerRadius: 10
		)
		guard let logoURL, let url = URL(string: logoURL),
				url.scheme == "https", url.host == "files.openai.com"
		else
		{
			return
		}
		if let cached = Self.cache.object(forKey: logoURL as NSString)
		{
			logo = cached
			return
		}
		loadTask = Task
		{
			[weak self] in
			guard let (data, _) = try? await URLSession.shared.data(from: url),
					data.count <= 2_000_000,
					!Task.isCancelled,
					let image = NSImage(data: data)
			else
			{
				return
			}
			Self.cache.setObject(
				image,
				forKey: logoURL as NSString
			)
			self?.logo = image
			self?.needsDisplay = true
		}
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	isolated deinit
	{
		loadTask?.cancel()
	}

	override func draw(_ dirtyRect: NSRect)
	{
		super.draw(dirtyRect)
		if let logo
		{
			logo.draw(in: bounds.insetBy(
				dx: 2,
				dy: 2
			))
		}
		else
		{
			DesktopIcons.draw(
				.plugin,
				in: bounds.insetBy(
					dx: 9,
					dy: 9
				),
				tint: AppKitColorTokens.settingsSecondaryText
			)
		}
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}
}
