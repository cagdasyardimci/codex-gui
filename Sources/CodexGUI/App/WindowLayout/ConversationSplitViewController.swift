import AppKit

@MainActor
final class ConversationSplitViewController: NSSplitViewController
{
	var onLayout: (() -> Void)?

	override func viewDidLayout()
	{
		super.viewDidLayout()
		onLayout?()
	}
}
