import AppKit
import UniformTypeIdentifiers

/// Local appearance controls.
@MainActor
final class SettingsAppearancePage: NSView, NSTextFieldDelegate
{
	private let preferences: TypographyPreferences
	private let center: NotificationCenter
	private let colorPreferences: ColorPreferences
	let modePicker = SettingsAppearanceModePicker()
	let presetPicker = SettingsChoicePicker(
		choices: [],
		presentation: .palette
	)
	let accentPicker = SettingsChoicePicker(
		choices: [],
		presentation: .palette
	)
	let accentField = NSTextField()
	let backgroundField = NSTextField()
	let foregroundField = NSTextField()
	let translucentSidebarSwitch = DesktopSwitch()
	private let accentWell = NSColorWell()
	private let backgroundWell = NSColorWell()
	private let foregroundWell = NSColorWell()
	private let contrastControl = SettingsSliderInput()
	var contrastSlider: DesktopSlider
	{
		contrastControl.slider
	}
	private var refreshingColors = false
	private weak var savePanel: NSSavePanel?
	private var displayedPresetAppearance: ColorAppearance?
	let uiSizeField = SettingsFormTextField(presentation: .compact)
	let contentSizeField = SettingsFormTextField(presentation: .compact)
	let codeSizeField = SettingsFormTextField(presentation: .compact)
	let uiFontPicker = SettingsChoicePicker(choices: [])
	let contentFontPicker = SettingsChoicePicker(choices: [])
	let codeFontPicker = SettingsChoicePicker(choices: [])
	private enum FontSetting
	{
		case ui, content, code
	}
	private let availableFontChoices = AppKitFontResolver.availableFontFamilies.map
	{
		SettingsChoicePicker.Choice(
			id: $0,
			title: $0
		)
	}

	private func fontChoices(for setting: FontSetting) -> [SettingsChoicePicker.Choice]
	{
		[SettingsChoicePicker.Choice(
			id: "",
			title: setting == .content ? "Same as UI font" : "System"
		)]
			+ availableFontChoices
	}
	private var observation: TypographyObservation?

	init(
		preferences: TypographyPreferences = TypographyPreferences(),
		colorPreferences: ColorPreferences = ColorPreferences(),
		center: NotificationCenter = .default
	)
	{
		self.preferences = preferences
		self.colorPreferences = colorPreferences
		self.center = center
		super.init(frame: .zero)
		let sizeRows = [
			makeRow(
				"UI font size",
				detail: "Adjust the base size used for Codex",
				field: uiSizeField,
				range: 11 ... 16
			),
			makeRow(
				"Content font size",
				detail: "Adjust the base size used for pages",
				field: contentSizeField,
				range: 12 ... 24
			),
			makeRow(
				"Code font size",
				detail: "Adjust the base size used for code across chats and diffs",
				field: codeSizeField,
				range: 8 ... 24
			),
		]
		modePicker.onSelect =
		{
			[weak self] mode in self?.changeMode(mode)
		}
		presetPicker.setAccessibilityLabel("Theme")
		presetPicker.onSelect =
		{
			[weak self] id in self?.changePreset(id)
		}
		accentPicker.setChoices(
			[.init(
				id: "custom",
				title: "Custom"
			)] + ColorNamedAccent.allCases.map
			{
				.init(
					id: $0.rawValue,
					title: $0.rawValue.capitalized
				)
			},
			selectedID: "default"
		)
		accentPicker.setAccessibilityLabel("Accent")
		accentPicker.onSelect =
		{
			[weak self] id in self?.changeAccentStyle(id)
		}
		configureColorInput(
			"Accent",
			field: accentField,
			well: accentWell
		)
		contrastSlider.target = self
		contrastSlider.action = #selector(changeContrast(_:))
		contrastSlider.isContinuous = true
		contrastSlider.setAccessibilityLabel("Contrast")
		translucentSidebarSwitch.target = self
		translucentSidebarSwitch.action = #selector(changeTranslucentSidebar(_:))
		translucentSidebarSwitch.setAccessibilityLabel("Translucent sidebar")
		let modeCard = SettingsPageLayout.section(
			title: "Visual style",
			rows: [
				SettingsPageLayout.row(
					title: "Mode",
					detail: nil,
					control: modePicker
				)
			]
		)
		let colorCard = SettingsPageLayout.card(rows: [
			SettingsPageLayout.row(
				title: "Theme",
				detail: nil,
				control: SettingsThemeControl(
					picker: presetPicker,
					onExport:
					{
						[weak self] in self?.exportTheme()
					},
					onCopy:
					{
						[weak self] in self?.copyTheme()
					}
				)
			),
			SettingsPageLayout.row(
				title: "Accent",
				detail: nil,
				control: accentPicker
			),
			makeColorRow(
				"Background",
				field: backgroundField,
				well: backgroundWell
			),
			makeColorRow(
				"Foreground",
				field: foregroundField,
				well: foregroundWell
			),
			makeFontRow(
				"Font",
				picker: uiFontPicker,
				setting: .ui
			),
		])
		let fontCard = SettingsPageLayout.card(rows: [
			makeFontRow(
				"Content font",
				picker: contentFontPicker,
				setting: .content
			),
			makeFontRow(
				"Code font",
				picker: codeFontPicker,
				setting: .code
			),
			SettingsPageLayout.row(
				title: "Translucent sidebar",
				detail: nil,
				control: translucentSidebarSwitch
			),
			SettingsPageLayout.row(
				title: "Contrast",
				detail: nil,
				control: contrastControl
			),
		])
		let advanced = SettingsDisclosureSection(
			title: "Advanced",
			cards: [
				SettingsPageLayout.card(rows: sizeRows),
				fontCard
			]
		)
		let document = SettingsPageLayout.document(
			title: "Appearance",
			sections: [modeCard, colorCard, advanced],
			columnWidth: .fitsViewport,
			presentation: .form
		)
		AppKitLayout.pin(
			document,
			to: self,
			inset: 0
		)
		observation = TypographyObservation(center: center)
		{
			[weak self] in self?.refresh()
		}
		center.addObserver(
			self,
			selector: #selector(colorPreferencesChanged),
			name: ColorPreferences.didChange,
			object: nil
		)
		refresh()
		refreshColors()
	}

	@objc private func colorPreferencesChanged()
	{
		refreshColors()
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	private func makeRow(
		_ title: String,
		detail: String,
		field: NSTextField,
		range: ClosedRange<Int>
	) -> NSView
	{
		let formatter = NumberFormatter()
		formatter.numberStyle = .decimal
		formatter.allowsFloats = false
		formatter.minimum = NSNumber(value: range.lowerBound)
		formatter.maximum = NSNumber(value: range.upperBound)
		field.formatter = formatter
		field.delegate = self
		field.target = self
		field.action = #selector(changeSize(_:))
		field.setAccessibilityLabel(title)
		return SettingsPageLayout.row(
			title: title,
			detail: detail,
			control: SettingsNumberInput(
				field: field,
				unit: "px"
			)
		)
	}

	private func makeFontRow(
		_ title: String,
		picker: SettingsChoicePicker,
		setting: FontSetting
	) -> NSView
	{
		picker.setChoices(
			fontChoices(for: setting),
			selectedID: ""
		)
		picker.setAccessibilityLabel(title)
		picker.onSelect =
		{
			[weak self] family in
			self?.updateProfile(
				fontSetting: setting,
				fontFamily: family.isEmpty ? nil : family
			)
		}
		return SettingsPageLayout.row(
			title: title,
			detail: nil,
			control: picker
		)
	}

	private func refreshFontPicker(
		_ picker: SettingsChoicePicker,
		family: String?,
		setting: FontSetting
	)
	{
		let fontChoices = fontChoices(for: setting)
		if let family, !fontChoices.contains(where:
			{
				$0.id == family
			})
		{
			picker.setChoices(
				fontChoices + [.init(
					id: family,
					title: family
				)],
				selectedID: family
			)
		}
		else
		{
			picker.select(id: family ?? "")
		}
	}

	private func configureColorInput(
		_ title: String,
		field: NSTextField,
		well: NSColorWell
	)
	{
		field.delegate = self
		field.target = self
		field.action = #selector(changeColor(_:))
		field.setAccessibilityLabel(title)
		well.setAccessibilityLabel(title)
		well.target = self
		well.action = #selector(changeColorWell(_:))
	}

	private func makeColorRow(
		_ title: String,
		field: NSTextField,
		well: NSColorWell
	) -> NSView
	{
		configureColorInput(
			title,
			field: field,
			well: well
		)
		return SettingsPageLayout.row(
			title: title,
			detail: nil,
			control: SettingsColorInput(
				field: field,
				well: well
			)
		)
	}

	private func themeData() -> Data?
	{
		let profile = editingDark ? colorPreferences.configuration.dark : colorPreferences
			.configuration.light
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		return try? encoder.encode(profile)
	}

	private func copyTheme()
	{
		guard let data = themeData(), let text = String(
			data: data,
			encoding: .utf8
		)
		else
		{
			return
		}
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(
			text,
			forType: .string
		)
	}

	private func exportTheme()
	{
		guard let window, savePanel?.sheetParent == nil, let data = themeData()
		else
		{
			return
		}
		savePanel = MarkdownDiagramExport.save(
			.init(
				data: data,
				contentType: .json,
				name: "Theme.json"
			),
			in: window
		)
	}

	override func viewWillMove(toWindow newWindow: NSWindow?)
	{
		if newWindow == nil, let panel = savePanel, let parent = panel.sheetParent
		{
			parent.endSheet(
				panel,
				returnCode: .cancel
			)
		}
		super.viewWillMove(toWindow: newWindow)
	}

	private var editingDark: Bool
	{
		switch colorPreferences.configuration.mode
		{
		case .dark: true
		case .light: false
		case .system: effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
		}
	}

	private func refreshColors()
	{
		guard !refreshingColors
		else
		{
			return
		}
		refreshingColors = true
		defer
		{
			refreshingColors = false
		}
		let configuration = colorPreferences.configuration
		modePicker.update(configuration: configuration)
		let profile = editingDark ? configuration.dark : configuration.light
		refreshFontPicker(
			uiFontPicker,
			family: profile.uiFontFamily,
			setting: .ui
		)
		refreshFontPicker(
			contentFontPicker,
			family: profile.contentFontFamily,
			setting: .content
		)
		refreshFontPicker(
			codeFontPicker,
			family: profile.codeFontFamily,
			setting: .code
		)
		let appearance: ColorAppearance = editingDark ? .dark : .light
		if displayedPresetAppearance != appearance
		{
			presetPicker.setChoices(
				[.init(
					id: "custom",
					title: "Custom"
				)] + ColorThemePresets.all.filter
				{
					$0.appearance == appearance
				}.map
				{
					.init(
						id: $0.id,
						title: $0.label
					)
				},
				selectedID: profile.presetID ?? "custom"
			)
			displayedPresetAppearance = appearance
		}
		presetPicker.select(id: profile.presetID ?? "custom")
		accentPicker.select(id: profile.namedAccent?.rawValue ?? "custom")
		let resolvedAccent = ColorPalette(
			configuration: profile,
			mode: editingDark ? .dark : .light
		).accent
		accentPicker.swatchColor = resolvedAccent
		contrastSlider.trackFillColor = resolvedAccent
		contrastSlider.needsDisplay = true
		let accentValue = hexValue(resolvedAccent) ?? profile.accent
		accentField.stringValue = String(
			format: "#%06X",
			accentValue
		)
		backgroundField.stringValue = String(
			format: "#%06X",
			profile.background
		)
		foregroundField.stringValue = String(
			format: "#%06X",
			profile.foreground
		)
		accentWell.color = rgbColor(accentValue)
		backgroundWell.color = rgbColor(profile.background)
		foregroundWell.color = rgbColor(profile.foreground)
		contrastControl.value = profile.contrast
		translucentSidebarSwitch.state = profile.opaqueWindows ? .off : .on
	}

	private func rgbColor(_ value: UInt32) -> NSColor
	{
		NSColor(
			srgbRed: CGFloat((value >> 16) & 255) / 255,
			green: CGFloat((value >> 8) & 255) / 255,
			blue: CGFloat(value & 255) / 255,
			alpha: 1
		)
	}

	private func hexValue(_ value: NSColor) -> UInt32?
	{
		guard let color = value.usingColorSpace(.sRGB)
		else
		{
			return nil
		}
		let byte: (CGFloat) -> UInt32 =
		{
			UInt32((min(
				1,
				max(
					0,
					$0
				)
			) * 255).rounded())
		}
		return byte(color.redComponent) << 16 | byte(color.greenComponent) << 8 |
			byte(color.blueComponent)
	}

	private func changeAccentStyle(_ id: String)
	{
		if let named = ColorNamedAccent(rawValue: id)
		{
			updateProfile(
				namedAccent: named,
				changeAccentSource: true
			)
			return
		}
		guard let window
		else
		{
			return
		}
		let dark = editingDark
		let prompt = DesktopTextEntryPrompt(
			title: "Accent color",
			actionTitle: "Apply",
			fields: [.init(
				value: accentField.stringValue,
				placeholder: "#RRGGBB",
				accessibilityLabel: "Accent color"
			)],
			layout: .single
		)
		prompt.beginSheet(in: window)
		{
			[weak self, weak window] values in
			guard let self, self.window === window, self.editingDark == dark,
					let text = values?.first, let rgb = self.rgbValue(text)
			else
			{
				return
			}
			self.updateProfile(accent: rgb)
		}
	}

	@objc private func changeColorWell(_ sender: NSColorWell)
	{
		guard !refreshingColors
		else
		{
			return
		}
		guard let color = sender.color.usingColorSpace(.sRGB)
		else
		{
			return
		}
		let byte: (CGFloat) -> UInt32 =
		{
			UInt32((min(
				1,
				max(
					0,
					$0
				)
			) * 255).rounded())
		}
		let rgb = byte(color.redComponent) << 16 | byte(color.greenComponent) << 8 |
			byte(color.blueComponent)
		updateProfile(
			accent: sender === accentWell ? rgb : nil,
			background: sender === backgroundWell ? rgb : nil,
			foreground: sender === foregroundWell ? rgb : nil
		)
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		refreshColors()
	}

	private func changeMode(_ mode: ColorThemeMode)
	{
		let old = colorPreferences.configuration
		colorPreferences.save(
			ColorThemeConfiguration(
				light: old.light,
				dark: old.dark,
				mode: mode
			),
			center: center
		)
		refreshColors()
	}

	private func changePreset(_ id: String)
	{
		let old = colorPreferences.configuration
		let dark = editingDark
		let current = dark ? old.dark : old.light
		let preset = ColorThemePresets.preset(
			id: id,
			appearance: dark ? .dark : .light
		)
		let selected = preset?.profile ?? current
		let updated = ColorThemeProfile(
			background: selected.background,
			foreground: selected.foreground,
			accent: selected.accent,
			contrast: selected.contrast,
			diffAdded: selected.diffAdded,
			diffRemoved: selected.diffRemoved,
			skill: selected.skill,
			namedAccent: selected.namedAccent,
			colorizeMessages: current.colorizeMessages,
			presetID: preset?.id,
			codeThemeID: preset?.codeTheme ?? current.codeThemeID,
			opaqueWindows: selected.opaqueWindows,
			hasCustomFonts: preset?.profile.hasCustomFonts ?? false
		)
		colorPreferences.save(
			ColorThemeConfiguration(
				light: dark ? old.light : updated,
				dark: dark ? updated : old.dark,
				mode: old.mode
			),
			center: center
		)
		refreshColors()
	}

	private func rgbValue(_ text: String) -> UInt32?
	{
		let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
		let digits = value.hasPrefix("#") ? String(value.dropFirst()) : value
		guard digits.utf8.count == 6,
				digits.utf8
				.allSatisfy(
				{
					(48 ... 57).contains($0) || (65 ... 70).contains($0) || (97 ... 102)
						.contains($0)
				}
				)
		else
		{
			return nil
		}
		return UInt32(
			digits,
			radix: 16
		)
	}

	@objc private func changeColor(_ sender: NSTextField)
	{
		guard let rgb = rgbValue(sender.stringValue)
		else
		{
			refreshColors(); return
		}
		if sender === accentField, rgb == hexValue(accentWell.color)
		{
			refreshColors()
			return
		}
		updateProfile(
			accent: sender === accentField ? rgb : nil,
			background: sender === backgroundField ? rgb : nil,
			foreground: sender === foregroundField ? rgb : nil
		)
	}

	@objc private func changeContrast(_ sender: NSSlider)
	{
		updateProfile(contrast: Int(sender.doubleValue.rounded()))
	}

	@objc private func changeTranslucentSidebar(_ sender: DesktopSwitch)
	{
		updateProfile(opaqueWindows: sender.state != .on)
	}

	private func updateProfile(
		accent: UInt32? = nil,
		background: UInt32? = nil,
		foreground: UInt32? = nil,
		contrast: Int? = nil,
		opaqueWindows: Bool? = nil,
		namedAccent: ColorNamedAccent? = nil,
		changeAccentSource: Bool = false,
		fontSetting: FontSetting? = nil,
		fontFamily: String? = nil
	)
	{
		let old = colorPreferences.configuration
		let dark = editingDark
		let profile = dark ? old.dark : old.light
		let updated = ColorThemeProfile(
			background: background ?? profile.background,
			foreground: foreground ?? profile.foreground,
			accent: accent ?? profile.accent,
			contrast: contrast ?? profile.contrast,
			diffAdded: profile.diffAdded,
			diffRemoved: profile.diffRemoved,
			skill: profile.skill,
			namedAccent: changeAccentSource ? namedAccent : accent == nil ? profile
				.namedAccent : nil,
			colorizeMessages: profile.colorizeMessages,
			presetID: profile.presetID,
			codeThemeID: profile.codeThemeID,
			opaqueWindows: opaqueWindows ?? profile.opaqueWindows,
			hasCustomFonts: profile.hasCustomFonts,
			uiFontFamily: fontSetting == .ui ? fontFamily : profile.uiFontFamily,
			contentFontFamily: fontSetting == .content ? fontFamily : profile.contentFontFamily,
			codeFontFamily: fontSetting == .code ? fontFamily : profile.codeFontFamily
		)
		colorPreferences.save(
			ColorThemeConfiguration(
				light: dark ? old.light : updated,
				dark: dark ? updated : old.dark,
				mode: old.mode
			),
			center: center
		)
		refreshColors()
	}

	func refresh()
	{
		let configuration = preferences.configuration
		uiSizeField.integerValue = Int(configuration.uiSize)
		contentSizeField.integerValue = Int(configuration.contentSize)
		codeSizeField.integerValue = Int(configuration.codeSize)
	}

	func controlTextDidEndEditing(_ notification: Notification)
	{
		guard let field = notification.object as? NSTextField
		else
		{
			return
		}
		if field === uiSizeField || field === contentSizeField || field === codeSizeField
		{
			changeSize(field)
		}
		else
		{
			changeColor(field)
		}
	}

	func control(
		_ control: NSControl,
		textView: NSTextView,
		doCommandBy commandSelector: Selector
	) -> Bool
	{
		guard control === uiSizeField || control === contentSizeField || control === codeSizeField,
				commandSelector == #selector(NSResponder.moveUp(_:)) || commandSelector ==
				#selector(NSResponder.moveDown(_:))
		else
		{
			return false
		}
		control
			.integerValue = (Int(textView.string) ?? control.integerValue) +
			(commandSelector == #selector(NSResponder.moveUp(_:)) ? 1 : -1)
		changeSize(control)
		return true
	}

	@objc private func changeSize(_ sender: NSControl)
	{
		let old = preferences.configuration
		let ui = sender === uiSizeField
		let content = sender === contentSizeField
		let value = CGFloat(sender.doubleValue)
		preferences.save(
			TypographyConfiguration(
				uiSize: ui ? value : old.uiSize,
				contentSize: content ? value : old.contentSize,
				codeSize: ui || content ? old.codeSize : value
			),
			center: center
		)
		refresh()
	}
}
