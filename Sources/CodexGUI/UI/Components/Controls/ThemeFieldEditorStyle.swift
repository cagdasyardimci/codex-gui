import AppKit

/// Applies theme colors to a borrowed field editor and restores its former colors on release.
@MainActor
final class ThemeFieldEditorStyle
{
	private weak var styledEditor: NSTextView?
	private var insertionPointColor: NSColor?
	private var selectedTextAttributes: [NSAttributedString.Key: Any]?

	func apply(
		to text: NSText,
		in view: NSView
	)
	{
		guard let editor = text as? NSTextView
		else
		{
			return
		}
		if styledEditor !== editor
		{
			insertionPointColor = editor.insertionPointColor
			selectedTextAttributes = editor.selectedTextAttributes
			styledEditor = editor
		}
		view.effectiveAppearance.performAsCurrentDrawingAppearance
		{
			let foreground = AppKitColorTokens.settingsPrimaryText
			editor.insertionPointColor = foreground
			var attributes = editor.selectedTextAttributes
			attributes[.backgroundColor] = AppKitColorTokens.selectionBackground
			attributes[.foregroundColor] = foreground
			editor.selectedTextAttributes = attributes
		}
		editor.needsDisplay = true
	}

	func restore(_ text: NSText)
	{
		guard let editor = text as? NSTextView, editor === styledEditor,
				let caret = insertionPointColor,
				let selection = selectedTextAttributes
		else
		{
			return
		}
		editor.insertionPointColor = caret
		editor.selectedTextAttributes = selection
		styledEditor = nil
		insertionPointColor = nil
		selectedTextAttributes = nil
	}
}
