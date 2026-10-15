import AppKit

/// Named native color roles. Dynamic providers remain unresolved until use.
@MainActor
enum AppKitColorTokens
{
	static let canvas = AppKitColorResolution.color(
		light: 0xFFFFFF,
		dark: 0x181818
	)
	static let slashMenu = AppKitColorResolution.color(
		light: 0xFFFFFF,
		dark: 0x2D2D2D
	)
	static let slashMenuSelection = AppKitColorResolution.color(
		light: 0xF1F2F2,
		dark: 0x3C3C3C
	)
	static let sidebar = AppKitColorResolution.color(
		light: 0xFBFBFB,
		dark: 0x1E1E1E
	)
	static let elevated = AppKitColorResolution.color(
		light: 0xF5F5F5,
		dark: 0x272727
	)
	static let terminalText = AppKitColorResolution.color(
		light: 0x606365,
		dark: 0xB9B9B9
	)
	static let terminalMutedText = AppKitColorResolution.color(
		light: 0x8C8F90,
		dark: 0x999999
	)
	static let inspector = AppKitColorResolution.color(
		light: 0xF4F4F4,
		dark: 0x2D2D2D
	)
	static let summaryCard = AppKitColorResolution.color(
		light: 0xFFFFFF,
		dark: 0x2D2D2D
	)
	static let chrome = AppKitColorResolution.color(
		light: 0xF6F6F6,
		dark: 0x282828
	)
	static let toolsShortcut = AppKitColorResolution.color(
		light: 0x1A1C1F,
		dark: 0xFFFFFF,
		lightAlpha: 0.065,
		darkAlpha: 0.065
	)
	static let selectedTab = AppKitColorResolution.color(
		light: 0xFFFFFF,
		dark: 0xFFFFFF,
		lightAlpha: 1,
		darkAlpha: 0.08
	)
	static let selectedTabEdge = AppKitColorResolution.color(
		light: 0x1A1C1F,
		dark: 0xFFFFFF,
		lightAlpha: 0.08,
		darkAlpha: 0.082
	)
	static let toolsCanvas = AppKitColorResolution.color(
		light: 0xFAFAFA,
		dark: 0x181818
	)
	static let toolsTile = AppKitColorResolution.color(
		light: 0xFFFFFF,
		dark: 0xFFFFFF,
		lightAlpha: 0.96,
		darkAlpha: 0.03
	)
	static let toolsTileIcon = AppKitColorResolution.color(
		light: 0x1A1C1F,
		dark: 0xFFFFFF,
		lightAlpha: 0.65,
		darkAlpha: 0.65
	)
	static let input = AppKitColorResolution.color(
		light: 0xF0F0F0,
		dark: 0x363636
	)
	static let selection = AppKitColorResolution.color(
		light: 0xE8E8E8,
		dark: 0x303030
	)
	static let border = AppKitColorResolution.color(
		light: 0xE4E4E4,
		dark: 0x363636
	)
	static let paneDivider = AppKitColorResolution.color(
		light: 0xE4E4E4,
		dark: 0x363636
	)
	static let highlightedPaneDivider = AppKitColorResolution.color(
		light: 0xD1D1D2,
		dark: 0x4A4A4A
	)
	static let userBubble = AppKitColorResolution.color(
		light: 0xE8F3FE,
		dark: 0x173E76
	)
	static let primaryText = AppKitColorResolution.color(
		light: 0x1A1C1F,
		dark: 0xFFFFFF
	)
	static let secondaryText = AppKitColorResolution.color(
		light: 0x1A1C1F,
		dark: 0xFFFFFF,
		lightAlpha: 0.494,
		darkAlpha: 0.498
	)
	static let composerPlaceholderText = AppKitColorResolution.color(
		light: 0x1A1C1F,
		dark: 0xFFFFFF,
		lightAlpha: 0.247,
		darkAlpha: 0.249
	)
	static let sidebarText = AppKitColorResolution.color(
		light: 0x1A1C1F,
		dark: 0xFFFFFF,
		lightAlpha: 0.85,
		darkAlpha: 0.85
	)
	static let captionText = AppKitColorResolution.color(
		light: 0x1A1C1F,
		dark: 0xFFFFFF,
		lightAlpha: 0.65,
		darkAlpha: 0.65
	)
	static let activityText = AppKitColorResolution.color(
		light: 0x1A1C1F,
		dark: 0xFFFFFF,
		lightAlpha: 0.6,
		darkAlpha: 0.6
	)
	static let mutedText = AppKitColorResolution.color(
		light: 0x1A1C1F,
		dark: 0xFFFFFF,
		lightAlpha: 0.4,
		darkAlpha: 0.4
	)
	static let userBubbleText = AppKitColorResolution.color(
		light: 0x0C274A,
		dark: 0xF6FAFE
	)
	static let composer = AppKitColorResolution.color(
		light: 0xFFFFFF,
		dark: 0x363636
	)
	static let composerSend = AppKitColorResolution.color(
		light: 0x3A83F7,
		dark: 0x3A83F7
	)
	static let composerEdge = AppKitColorResolution.color(
		light: 0x000000,
		dark: 0xFFFFFF,
		lightAlpha: 0.04,
		darkAlpha: 0
	)
	static let composerInsetEdge = AppKitColorResolution.color(
		light: 0xFFFFFF,
		dark: 0xFFFFFF,
		lightAlpha: 0,
		darkAlpha: 0.2
	)
	static let rowHighlight = AppKitColorResolution.color(
		light: 0x1A1C1F,
		dark: 0xFFFFFF,
		lightAlpha: 0.055,
		darkAlpha: 0.08
	)
	static let toggleHighlight = AppKitColorResolution.color(
		light: 0x1A1C1F,
		dark: 0xFFFFFF,
		lightAlpha: 0.05,
		darkAlpha: 0.05
	)
	static let subtleEdge = AppKitColorResolution.color(
		light: 0x1A1C1F,
		dark: 0xFFFFFF,
		lightAlpha: 0.047,
		darkAlpha: 0.043
	)
	static let summaryEdge = AppKitColorResolution.color(
		light: 0x1A1C1F,
		dark: 0xFFFFFF,
		lightAlpha: 0.118,
		darkAlpha: 0.157
	)
	static let popover = AppKitColorResolution.color(
		light: 0xFFFFFF,
		dark: 0x2D2D2D,
		lightAlpha: 0.9,
		darkAlpha: 0.9
	)
	static let popoverEdge = AppKitColorResolution.color(
		light: 0x1A1C1F,
		dark: 0xFFFFFF,
		lightAlpha: 0.08,
		darkAlpha: 0.082
	)
	static let fullAccess = AppKitColorResolution.color(
		light: 0xE25507,
		dark: 0xFF8549
	)
	static let inlineCode = AppKitColorResolution.color(
		light: 0x1A1C1F,
		dark: 0xFFFFFF,
		lightAlpha: 0.0929412,
		darkAlpha: 0.09
	)

	static let effortBlue = NSColor(
		srgbRed: 0x3A / 255.0,
		green: 0x83 / 255.0,
		blue: 0xF7 / 255.0,
		alpha: 1
	)
	static let effortTrack = AppKitColorResolution.color(
		light: 0x1A1C1F,
		dark: 0xFFFFFF,
		lightAlpha: 0.1,
		darkAlpha: 0.1
	)
	static let effortTick = AppKitColorResolution.color(
		light: 0x1A1C1F,
		dark: 0xFFFFFF,
		lightAlpha: 0.247059,
		darkAlpha: 0.24902
	)
	static let effortFilledTick = NSColor.white.withAlphaComponent(0.3)
	static let effortThumb = NSColor.white
	static let effortTrackEdge = AppKitColorResolution.color(
		light: 0x1A1C1F,
		dark: 0xFFFFFF,
		lightAlpha: 0.08,
		darkAlpha: 0.082
	)
	static let effortModel = AppKitColorResolution.color(
		light: 0x1A1C1F,
		dark: 0xFFFFFF,
		lightAlpha: 0.65,
		darkAlpha: 0.65
	)
	static let effortIcon = AppKitColorResolution.color(
		light: 0x6B6B6B,
		dark: 0xA0A0A0
	)

	static let approvalRowHover = AppKitColorResolution.color(
		light: 0xF4F3F3,
		dark: 0xFFFFFF,
		darkAlpha: 0.08
	)
	static let approvalPrimary = AppKitColorResolution.grayscaleColor(
		light: 0.13,
		dark: 1
	)
	static let approvalSecondary = AppKitColorResolution.adaptiveColor
	{
		appearance in
		appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
			? NSColor.white.withAlphaComponent(0.498) : NSColor(
				white: 0.57,
				alpha: 1
			)
	}
	static let approvalIcon = AppKitColorResolution.grayscaleColor(
		light: 0.33,
		dark: 1
	)

	static let transcriptLink = AppKitColorResolution.adaptiveColor
	{
		appearance in
		appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
			? NSColor(
				srgbRed: 87.0 / 255,
				green: 133.0 / 255,
				blue: 209.0 / 255,
				alpha: 1
			) : .linkColor
	}

}
