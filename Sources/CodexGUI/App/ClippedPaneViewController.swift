import AppKit

/// Lets a split viewport narrow below its content's supported layout width without scaling text.
@MainActor
final class ClippedPaneViewController: NSViewController
{
	private let contentController: NSViewController
	private let minimumContentWidth: CGFloat
	private var presentedController: NSViewController?

	init(
		content: NSViewController,
		minimumContentWidth: CGFloat
	)
	{
		contentController = content
		self.minimumContentWidth = minimumContentWidth
		presentedController = content
		super.init(
			nibName: nil,
			bundle: nil
		)
		addChild(content)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func loadView()
	{
		view = ClippedPaneViewport(
			content: presentedController?.view,
			minimumContentWidth: minimumContentWidth
		)
	}

	/// Transfers the live controller without leaving another viewport responsible for its frame.
	func detachContent()
	{
		(view as? ClippedPaneViewport)?.setContent(
			nil,
			minimumWidth: minimumContentWidth
		)
		presentedController?.removeFromParent()
		presentedController = nil
	}

	func restoreContent()
	{
		present(
			contentController,
			minimumWidth: minimumContentWidth
		)
	}

	func present(
		_ controller: NSViewController,
		minimumWidth: CGFloat
	)
	{
		guard presentedController !== controller
		else
		{
			return
		}
		detachContent()
		controller.removeFromParent()
		addChild(controller)
		presentedController = controller
		(view as? ClippedPaneViewport)?.setContent(
			controller.view,
			minimumWidth: minimumWidth
		)
		view.layoutSubtreeIfNeeded()
	}

}

/// The content's minimum width must not become the split item's minimum width.
private final class ClippedPaneViewport: NSView
{
	private var content: NSView?
	private let mainRegion = NSView()
	private var minimumContentWidth: CGFloat

	init(
		content: NSView?,
		minimumContentWidth: CGFloat
	)
	{
		self.minimumContentWidth = minimumContentWidth
		super.init(frame: .zero)
		clipsToBounds = true
		mainRegion.clipsToBounds = true
		mainRegion.autoresizingMask = []
		addSubview(mainRegion)
		setContent(
			content,
			minimumWidth: minimumContentWidth
		)
	}

	func setContent(
		_ content: NSView?,
		minimumWidth: CGFloat
	)
	{
		self.content?.removeFromSuperview()
		self.content = content
		minimumContentWidth = minimumWidth
		guard let content
		else
		{
			return
		}
		// No width constraint crosses the clipping boundary. The native divider can therefore
		// move all the way to zero while the content retains a supported layout width.
		content.translatesAutoresizingMaskIntoConstraints = true
		content.autoresizingMask = []
		mainRegion.addSubview(content)
		needsLayout = true
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func setFrameSize(_ newSize: NSSize)
	{
		super.setFrameSize(newSize)
		needsLayout = true
	}

	override func layout()
	{
		super.layout()
		guard let content
		else
		{
			return
		}
		mainRegion.frame = NSRect(
			x: bounds.minX,
			y: bounds.minY,
			width: bounds.width,
			height: bounds.height
		)
		let contentFrame = NSRect(
			x: 0,
			y: 0,
			width: max(
				minimumContentWidth,
				bounds.width
			),
			height: bounds.height
		)
		if content.frame != contentFrame
		{
			content.frame = contentFrame
		}
		content.layoutSubtreeIfNeeded()
	}
}
