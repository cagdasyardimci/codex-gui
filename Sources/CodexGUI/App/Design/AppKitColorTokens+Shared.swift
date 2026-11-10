import AppKit

extension AppKitColorTokens
{
	// Shared surface, interaction and icon configurations. Context-specific names
	// alias these without repeating palette selection or opacity policy.
	// This theme swatch also fills inverse controls; text and fill keep semantic aliases.
	static var foreground: NSColor
	{
		paletteColor
		{
			$0.foreground
		}
	}
	static var hoverOverlay: NSColor
	{
		paletteColor
		{
			$0.hoverOverlay
		}
	}
	static var selectedOverlay: NSColor
	{
		paletteColor
		{
			$0.selectedOverlay
		}
	}
	static var elevatedOpaque: NSColor
	{
		paletteColor
		{
			$0.elevatedOpaque
		}
	}
	static var elevatedSecondaryOpaque: NSColor
	{
		paletteColor
		{
			$0.elevatedSecondaryOpaque
		}
	}
	static var skill: NSColor
	{
		paletteColor
		{
			$0.skill
		}
	}
	static var primaryIcon: NSColor
	{
		paletteColor
		{
			$0.primaryIcon
		}
	}
	static var secondaryIcon: NSColor
	{
		paletteColor
		{
			$0.secondaryIcon
		}
	}
	static var tertiaryIcon: NSColor
	{
		paletteColor
		{
			$0.tertiaryIcon
		}
	}
	static var accentSurface: NSColor
	{
		paletteColor
		{
			$0.accentBackground
		}
	}
}
