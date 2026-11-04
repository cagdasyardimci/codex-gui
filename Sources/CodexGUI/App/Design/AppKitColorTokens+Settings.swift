import AppKit

extension AppKitColorTokens
{
	static var settingsCard: NSColor
	{
		paletteColor
		{
			$0.formCard
		}
	}
	static var settingsPrimaryText: NSColor
	{
		primaryText
	}
	static var settingsSecondaryText: NSColor
	{
		captionText
	}
	static var settingsTertiaryText: NSColor
	{
		secondaryText
	}
	static var settingsSidebarSurface: NSColor
	{
		paletteColor
		{
			$0.controlOpaque.withAlphaComponent(0.65)
		}
	}
	static var settingsCatalogSearchSurface: NSColor
	{
		input
	}
	static var settingsCatalogSearchEdge: NSColor
	{
		heavyBorder
	}
	static var settingsHeaderActionSurface: NSColor
	{
		input
	}
	static var settingsHeaderActionEdge: NSColor
	{
		border
	}
	static var settingsHeaderPrimaryText: NSColor
	{
		controlSurface
	}
	static var settingsFormFieldSurface: NSColor
	{
		input
	}
	static var settingsSelectorSurface: NSColor
	{
		input
	}
	static var settingsSelectorEdge: NSColor
	{
		border
	}
	static var settingsSelectorHover: NSColor
	{
		hoverOverlay
	}
	static var settingsFieldFocus: NSColor
	{
		focus
	}
	static var settingsFieldError: NSColor
	{
		errorText
	}
	static var settingsSearchSurface: NSColor
	{
		hoverOverlay
	}
	static var settingsSidebarSelection: NSColor
	{
		hoverOverlay
	}
	static var settingsSearchEditorSurface: NSColor
	{
		paletteColor
		{
			p in
			let overlay = p.hoverOverlay
			return p.surface.blended(
				withFraction: overlay.alphaComponent,
				of: overlay.withAlphaComponent(1)
			) ?? p.surface
		}
	}

}
