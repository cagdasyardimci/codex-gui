import Foundation

/// Pointer hover and keyboard focus independently keep an action glyph visible.
struct DesktopActionRevealState
{
	var isHovered = false
	var isKeyboardFocused = false

	var isRevealed: Bool
	{
		isHovered || isKeyboardFocused
	}
}
