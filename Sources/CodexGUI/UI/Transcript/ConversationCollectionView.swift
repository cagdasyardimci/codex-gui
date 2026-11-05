import AppKit

/// Preserves descendant focus when AppKit forwards tab commands through the collection.
@MainActor
final class ConversationCollectionView: NSCollectionView
{
	override func insertTab(_ sender: Any?)
	{
		if let window, let focused = window.firstResponder as? NSView,
			focused !== self, focused.isDescendant(of: self)
		{
			window.selectKeyView(following: focused)
			return
		}
		super.insertTab(sender)
	}

	override func insertBacktab(_ sender: Any?)
	{
		if let window, let focused = window.firstResponder as? NSView,
			focused !== self, focused.isDescendant(of: self)
		{
			window.selectKeyView(preceding: focused)
			return
		}
		super.insertBacktab(sender)
	}
}
