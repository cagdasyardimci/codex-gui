import AppKit

/// Named native color roles. Dynamic providers remain unresolved until use.
@MainActor
enum AppKitColorTokens
{
	/// Resolves a semantic role against the current theme and the owning appearance.
	static func paletteColor(_ role: @escaping (ColorPalette) -> NSColor) -> NSColor
	{
		AppKitColorResolution.adaptiveColor
		{
			appearance in
			let configuration = ColorPreferences().configuration
			let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
			let mode: ColorAppearance = dark ? .dark : .light
			let profile = dark ? configuration.dark : configuration.light
			return role(ColorPalette(
				configuration: profile,
				mode: mode
			))
		}
	}
	static var canvas: NSColor
	{
		paletteColor
		{
			$0.surface
		}
	}
	/// ChatGPT's primary outline role, resolved over the notice surface.
	static var chatLockEdge: NSColor
	{
		heavyBorder
	}
	static var chatLockDivider: NSColor
	{
		border
	}
	static var chatLockActionHover: NSColor
	{
		hoverOverlay
	}
	static var slashMenu: NSColor
	{
		elevatedOpaque
	}
	static var slashMenuSelection: NSColor
	{
		hoverOverlay
	}
	static var sidebar: NSColor
	{
		paletteColor
		{
			$0.surfaceUnder
		}
	}
	static var searchPanel: NSColor
	{
		controlSurface
	}
	static var searchResultSelection: NSColor
	{
		paletteColor
		{
			$0.controlHoverOpaque
		}
	}
	static var elevated: NSColor
	{
		paletteColor
		{
			$0.elevated
		}
	}
	static var terminalText: NSColor
	{
		primaryText
	}
	static var terminalOutputText: NSColor
	{
		paletteColor
		{
			$0.descriptionText
		}
	}
	static var terminalMutedText: NSColor
	{
		secondaryText
	}
	static var inspector: NSColor
	{
		editorSurface
	}
	static var summaryCard: NSColor
	{
		elevatedOpaque
	}
	static var chrome: NSColor
	{
		editorSurface
	}
	static var toolsShortcut: NSColor
	{
		hoverOverlay
	}
	static var fileSearchSnippet: NSColor
	{
		captionText
	}
	static var fileSearchLocation: NSColor
	{
		secondaryText
	}
	static var fileSearchSelectedLocation: NSColor
	{
		captionText
	}
	static var fileSearchMatch: NSColor
	{
		selectionBackground
	}
	static var fileSearchSelection: NSColor
	{
		hoverOverlay
	}
	static var fileSearchKeycap: NSColor
	{
		hoverOverlay
	}
	static var fileSearchEscape: NSColor
	{
		selectedOverlay
	}
	static var fileSearchDivider: NSColor
	{
		border
	}
	static var selectedTab: NSColor
	{
		selectedOverlay
	}
	static var selectedTabEdge: NSColor
	{
		border
	}
	static var toolsCanvas: NSColor
	{
		canvas
	}
	static var toolsTile: NSColor
	{
		elevated
	}
	static var toolsTileIcon: NSColor
	{
		secondaryIcon
	}
	static var input: NSColor
	{
		paletteColor
		{
			$0.control
		}
	}
	static var selection: NSColor
	{
		hoverOverlay
	}
	static var border: NSColor
	{
		paletteColor
		{
			$0.border
		}
	}
	static var paneDivider: NSColor
	{
		border
	}
	static var highlightedPaneDivider: NSColor
	{
		heavyBorder
	}
	static var userBubble: NSColor
	{
		paletteColor
		{
			$0.messageBackground
		}
	}
	static func viewerControlSelection(active: Bool) -> NSColor
	{
		paletteColor
		{
			$0.viewerControlSelection(active: active)
		}
	}
	static var viewerControlSelectedText: NSColor
	{
		paletteColor
		{
			$0.viewerControlSelectedText
		}
	}
	static var viewerControlSelectionEdge: NSColor
	{
		paletteColor
		{
			$0.accentText.withAlphaComponent(0.2)
		}
	}
	static var primaryText: NSColor
	{
		foreground
	}
	static var secondaryText: NSColor
	{
		paletteColor
		{
			$0.tertiaryText
		}
	}
	static var composerPlaceholderText: NSColor
	{
		paletteColor
		{
			$0.foreground.withAlphaComponent(0.25)
		}
	}
	static var sidebarText: NSColor
	{
		paletteColor
		{
			$0.foreground.withAlphaComponent(0.85)
		}
	}
	static var captionText: NSColor
	{
		paletteColor
		{
			$0.secondaryText
		}
	}
	static var activityText: NSColor
	{
		captionText
	}
	static var mutedText: NSColor
	{
		paletteColor
		{
			$0.foreground.withAlphaComponent(0.4)
		}
	}
	static var userBubbleText: NSColor
	{
		paletteColor
		{
			$0.messageText
		}
	}
	static var composer: NSColor
	{
		elevated
	}
	static var tooltipCapsule: NSColor
	{
		paletteColor
		{
			$0.tooltipCapsule
		}
	}
	static var composerQueue: NSColor
	{
		elevated
	}
	static var composerQueueLeadingGlyph: NSColor
	{
		tertiaryIcon
	}
	static var composerQueueDivider: NSColor
	{
		subtleEdge
	}
	static var composerPrimaryText: NSColor
	{
		primaryText
	}
	static var composerSecondaryText: NSColor
	{
		secondaryText
	}
	static var composerControlDivider: NSColor
	{
		border
	}

	static var composerMenuRowHover: NSColor
	{
		hoverOverlay
	}
	static var composerSend: NSColor
	{
		paletteColor
		{
			$0.composerFill
		}
	}
	static var composerEdge: NSColor
	{
		subtleEdge
	}
	static var composerInsetEdge: NSColor
	{
		heavyBorder
	}
	static var rowHighlight: NSColor
	{
		hoverOverlay
	}
	static var toggleHighlight: NSColor
	{
		hoverOverlay
	}
	static var subtleEdge: NSColor
	{
		paletteColor
		{
			$0.lightBorder
		}
	}
	static var summaryEdge: NSColor
	{
		heavyBorder
	}
	static var popover: NSColor
	{
		elevated
	}
	static var popoverEdge: NSColor
	{
		border
	}
	static var fullAccess: NSColor
	{
		warningText
	}
	static var inlineCode: NSColor
	{
		paletteColor
		{
			$0.inlineCode
		}
	}

	static var effortBlue: NSColor
	{
		accent
	}
	static var effortTrack: NSColor
	{
		paletteColor
		{
			$0.foreground.withAlphaComponent(0.1)
		}
	}
	static var effortTick: NSColor
	{
		paletteColor
		{
			$0.foreground.withAlphaComponent(0.25)
		}
	}
	static var effortFilledTick: NSColor
	{
		paletteColor
		{
			$0.onAccent.withAlphaComponent(0.3)
		}
	}
	static var effortThumb: NSColor
	{
		switchThumb(on: true)
	}
	static var effortTrackEdge: NSColor
	{
		border
	}
	static var effortModel: NSColor
	{
		captionText
	}
	static var effortIcon: NSColor
	{
		secondaryIcon
	}

	static var approvalRowHover: NSColor
	{
		hoverOverlay
	}
	static var approvalPrimary: NSColor
	{
		primaryText
	}
	static var approvalSecondary: NSColor
	{
		secondaryText
	}
	static var approvalIcon: NSColor
	{
		primaryIcon
	}

	static var composerSkillMention: NSColor
	{
		skill
	}

	static var transcriptLink: NSColor
	{
		accentText
	}

}
