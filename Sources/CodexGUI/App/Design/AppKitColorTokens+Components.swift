import AppKit

extension AppKitColorTokens
{
	static var accentText: NSColor
	{
		paletteColor
		{
			$0.accentText
		}
	}
	static var inlineReferenceText: NSColor
	{
		paletteColor
		{
			$0.inlineReferenceText
		}
	}
	static var diffAdded: NSColor
	{
		paletteColor
		{
			$0.diffAdded
		}
	}
	static var diffRemoved: NSColor
	{
		paletteColor
		{
			$0.diffRemoved
		}
	}
	static var errorText: NSColor
	{
		paletteColor
		{
			$0.errorText
		}
	}
	static var warningText: NSColor
	{
		paletteColor
		{
			$0.warningText
		}
	}
	static var effortUltra: NSColor
	{
		skill
	}
	static var capabilityInternet: NSColor
	{
		accentText
	}
	static var disabledText: NSColor
	{
		mutedText
	}
	static var editorSurface: NSColor
	{
		paletteColor
		{
			$0.editor
		}
	}
	static var controlSurface: NSColor
	{
		paletteColor
		{
			$0.controlOpaque
		}
	}
	static var avatarText: NSColor
	{
		paletteColor
		{
			$0.avatarText
		}
	}
	static var onAccent: NSColor
	{
		paletteColor
		{
			$0.onAccent
		}
	}
	static var tooltipText: NSColor
	{
		paletteColor
		{
			$0.tooltipText
		}
	}
	static var tooltipBorder: NSColor
	{
		paletteColor
		{
			$0.tooltipText.withAlphaComponent(0.05)
		}
	}
	static var tooltipKeycap: NSColor
	{
		paletteColor
		{
			$0.tooltipText.withAlphaComponent(0.25)
		}
	}
	static var fileChangeSurface: NSColor
	{
		elevatedOpaque
	}
	static var imageCanvas: NSColor
	{
		canvas
	}
	static var imageControlSurface: NSColor
	{
		paletteColor
		{
			$0.viewerControlSurface
		}
	}
	static var imageControlHover: NSColor
	{
		paletteColor
		{
			$0.viewerControlHover
		}
	}
	static var imageControlText: NSColor
	{
		primaryText
	}
	static var popoverScrim: NSColor
	{
		paletteColor
		{
			$0.scrim(opacity: 0.14)
		}
	}
	static var pairingScrim: NSColor
	{
		paletteColor
		{
			$0.scrim(opacity: 0.3)
		}
	}
	static var imageScrim: NSColor
	{
		paletteColor
		{
			$0.scrim(opacity: 0.92)
		}
	}
	static var sidebarTranslucentTint: NSColor
	{
		paletteColor
		{
			$0.sidebarTint
		}
	}
	static var sidebarOpaque: NSColor
	{
		paletteColor
		{
			$0.sidebarOpaque
		}
	}
	static var sidebarMoreText: NSColor
	{
		paletteColor
		{
			$0.tertiaryText.withAlphaComponent($0.tertiaryText.alphaComponent * 0.7)
		}
	}
	static var toolbarPressed: NSColor
	{
		paletteColor
		{
			$0.foreground.withAlphaComponent(0.16)
		}
	}
	static var shortcutSurface: NSColor
	{
		paletteColor
		{
			$0.foreground.withAlphaComponent(0.12)
		}
	}
	static var uncheckedControlEdge: NSColor
	{
		paletteColor
		{
			$0.tertiaryText.withAlphaComponent(0.25)
		}
	}
	static var switchOff: NSColor
	{
		paletteColor
		{
			$0.foreground.withAlphaComponent(0.1)
		}
	}
	static func switchThumb(on: Bool) -> NSColor
	{
		paletteColor
		{
			$0.switchThumb(on: on)
		}
	}
	// A broad validation halo needs less opacity than the output card's thin edge.
	static var fieldErrorEdge: NSColor
	{
		paletteColor
		{
			$0.errorText.withAlphaComponent(0.2)
		}
	}
	static var errorCardSurface: NSColor
	{
		paletteColor
		{
			$0.errorText.withAlphaComponent(0.1)
		}
	}
	static var errorCardEdge: NSColor
	{
		paletteColor
		{
			$0.errorText.withAlphaComponent(0.3)
		}
	}
	static var usageGrid: NSColor
	{
		paletteColor
		{
			$0.secondaryText.withAlphaComponent(0.18)
		}
	}
	static var usageLabel: NSColor
	{
		paletteColor
		{
			$0.foreground.withAlphaComponent(0.82)
		}
	}
	static var turnRail: NSColor
	{
		paletteColor
		{
			$0.foreground.withAlphaComponent(0.2)
		}
	}
	static var terminalFadeOpaque: NSColor
	{
		paletteColor
		{
			$0.elevated.withAlphaComponent(0.95)
		}
	}
	static var terminalFadeClear: NSColor
	{
		paletteColor
		{
			$0.elevated.withAlphaComponent(0)
		}
	}
	static var diffDivider: NSColor
	{
		paletteColor
		{
			$0.border.withAlphaComponent(0.35)
		}
	}
	static var fileCodeSurface: NSColor
	{
		paletteColor
		{
			$0.foreground.withAlphaComponent(0.00549)
		}
	}
	static var contextProgressTrack: NSColor
	{
		paletteColor
		{
			$0.tertiaryText.withAlphaComponent(0.55)
		}
	}

	static var focus: NSColor
	{
		paletteColor
		{
			$0.focus
		}
	}
	static var accent: NSColor
	{
		paletteColor
		{
			$0.accent
		}
	}
	static var selectionBackground: NSColor
	{
		paletteColor
		{
			$0.selectionBackground
		}
	}
	static var heavyBorder: NSColor
	{
		paletteColor
		{
			$0.heavyBorder
		}
	}
	static var composerSendText: NSColor
	{
		paletteColor
		{
			$0.composerText
		}
	}
	static var diffAddedContent: NSColor
	{
		paletteColor
		{
			$0.diffBackground(
				added: true,
				gutter: false
			)
		}
	}
	static var diffRemovedContent: NSColor
	{
		paletteColor
		{
			$0.diffBackground(
				added: false,
				gutter: false
			)
		}
	}
	static var diffAddedGutter: NSColor
	{
		paletteColor
		{
			$0.diffBackground(
				added: true,
				gutter: true
			)
		}
	}
	static var diffRemovedGutter: NSColor
	{
		paletteColor
		{
			$0.diffBackground(
				added: false,
				gutter: true
			)
		}
	}
	static func diffSelection(
		over color: NSColor,
		gutter: Bool
	) -> NSColor
	{
		paletteColor
		{
			$0.diffSelection(
				over: color,
				gutter: gutter
			)
		}
	}

	// Preserve the operating system's focus indication as a platform accessibility contract.
	static var platformFocus: NSColor
	{
		.keyboardFocusIndicatorColor
	}

	static func copySurface(code: Bool) -> NSColor
	{
		paletteColor
		{
			$0.foreground.withAlphaComponent(code ? 0.1 : 0.06)
		}
	}

	static func enabledForeground(
		_ foreground: NSColor,
		enabled: Bool
	) -> NSColor
	{
		AppKitColorResolution.adaptiveColor
		{
			appearance in
			var result = foreground
			appearance.performAsCurrentDrawingAppearance
			{
				result = enabled ? foreground : foreground
					.withAlphaComponent(foreground.alphaComponent * 0.4)
			}
			return result
		}
	}

	static let imageBackdropOpacity: CGFloat = 0.5
	static let diagramBackdropOpacity: CGFloat = 0.9
	static let disabledMenuOpacity: CGFloat = 0.5
	static let inactiveMenuIconOpacity: CGFloat = 0.75

	static func imageBackdrop(opacity: CGFloat) -> NSColor
	{
		paletteColor
		{
			$0.imageBackdrop(opacity: opacity)
		}
	}

	static func diagramBackdrop(opacity: CGFloat) -> NSColor
	{
		paletteColor
		{
			$0.scrim(opacity: opacity)
		}
	}

	static func diffSpan(
		added: Bool,
		unified: Bool = false
	) -> NSColor
	{
		paletteColor
		{
			(added ? $0.diffAdded : $0.diffRemoved).withAlphaComponent(unified ? 0.30 : 0.24)
		}
	}
	static func sidebarButtonSurface(pressed: Bool) -> NSColor
	{
		paletteColor
		{
			$0.foreground.withAlphaComponent(pressed ? 0.16 : 0.08)
		}
	}
	static func primaryButtonSurface(
		enabled: Bool,
		active: Bool
	) -> NSColor
	{
		paletteColor
		{
			$0.foreground.withAlphaComponent(!enabled ? 0.4 : active ? 0.8 : 1)
		}
	}
	static func destructiveButtonSurface(
		enabled: Bool,
		active: Bool
	) -> NSColor
	{
		paletteColor
		{
			$0.errorText.withAlphaComponent(enabled ? (active ? 0.2 : 0.1) : 0.04)
		}
	}
	static func selectedButtonTab(active: Bool) -> NSColor
	{
		paletteColor
		{
			$0.foreground.withAlphaComponent(active ? 0.1 : 0.05)
		}
	}
	static func headerButtonSurface(
		primary: Bool,
		active: Bool,
		enabled: Bool
	) -> NSColor
	{
		paletteColor
		{
			p in
			let color = primary ? p.foreground : active ? p.hoverOverlay : p.control
			return color
				.withAlphaComponent(color
					.alphaComponent * (!enabled ? 0.4 : primary && active ? 0.8 : 1))
		}
	}

	static func richContentColors(
		appearance: NSAppearance,
		configuration: ColorThemeConfiguration
	) -> [String: String]
	{
		let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
		let p = ColorPalette(
			configuration: configuration.profile(for: dark ? .dark : .light),
			mode: dark ? .dark : .light
		)
		func css(_ color: NSColor) -> String
		{
			let c = color.usingColorSpace(.sRGB)!
			let channels = [c.redComponent, c.greenComponent, c.blueComponent]
				.map
				{
					String(Int(($0 * 255).rounded()))
				}
			return "rgba(" + channels.joined(separator: ",") + ",\(c.alphaComponent))"
		}
		return [
			"text": css(p.foreground),
			"canvas": css(p.surface),
			"fill": css(p.accentBackground),
			"stateLabelFill": css(p.accentBackground.withAlphaComponent(0.5)),
			"pieOpacity": "0.7",
			"border": css(p.accentText),
			"secondary": css(p.elevatedOpaque),
			"tertiary": css(p.panel),
			"edge": css(p.tertiaryText),
			"cluster": css(p.panel),
			"outline": css(p.diagramOutline),
			"noteBorder": css(p.diffAdded),
			"ink": css(p.accentText),
			"root": css(p.accentBackground),
			"chart1": css(p.accent),
			"chart2": css(p.diffAdded),
			"chart3": css(p.warningText),
			"chart4": css(p.skill)
		]
	}

}
