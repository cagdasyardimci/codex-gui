import AppKit

/// Lets a split viewport narrow below its content's supported layout width without scaling text.
@MainActor
final class ClippedPaneViewController: NSViewController
{
	private let contentController: NSViewController
	private let minimumContentWidth: CGFloat
	private var presentedController: NSViewController?
	private var asideController: NSViewController?

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
		setAside(
			nil,
			width: 0
		)
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

	func setAside(
		_ controller: NSViewController?,
		width: CGFloat
	)
	{
		guard controller !== presentedController
		else
		{
			return
		}
		if asideController !== controller
		{
			(view as? ClippedPaneViewport)?.setAside(
				nil,
				width: 0
			)
			asideController?.removeFromParent()
			asideController = controller
			if let controller
			{
				controller.removeFromParent()
				addChild(controller)
			}
		}
		(view as? ClippedPaneViewport)?.setAside(
			controller?.view,
			width: width
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
	private var minimumContentHeight: CGFloat = 0
	private var aside: NSView?
	private var asideWidth: CGFloat = 0
	private var minimumAsideHeight: CGFloat = 0

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
		// Measure while detached, before a zero frame can produce autoresizing constraints.
		minimumContentHeight = content.fittingSize.height
		updateContentFrames()
		content.translatesAutoresizingMaskIntoConstraints = true
		content.autoresizingMask = []
		mainRegion.addSubview(content)
		needsLayout = true
	}

	func setAside(
		_ aside: NSView?,
		width: CGFloat
	)
	{
		asideWidth = aside == nil ? 0 : max(
			0,
			width
		)
		if self.aside !== aside
		{
			self.aside?.removeFromSuperview()
			self.aside = aside
			if let aside
			{
				minimumAsideHeight = aside.fittingSize.height
				updateContentFrames()
				aside.translatesAutoresizingMaskIntoConstraints = true
				aside.autoresizingMask = []
				addSubview(aside)
			}
		}
		updateContentFrames()
		needsLayout = true
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func setFrameSize(_ newSize: NSSize)
	{
		super.setFrameSize(newSize)
		updateContentFrames()
		needsLayout = true
	}

	override func layout()
	{
		updateContentFrames()
		super.layout()
		aside?.layoutSubtreeIfNeeded()
		content?.layoutSubtreeIfNeeded()
	}

	/// Update frames before Auto Layout visits descendants, including before first attachment.
	private func updateContentFrames()
	{
		let visibleAsideWidth = min(
			asideWidth,
			bounds.width
		)
		let visibleContentWidth = bounds.width - visibleAsideWidth

		mainRegion.frame = NSRect(
			x: bounds.minX,
			y: bounds.minY,
			width: visibleContentWidth,
			height: bounds.height
		)
		let contentFrame = NSRect(
			x: 0,
			y: 0,
			width: max(
				minimumContentWidth,
				visibleContentWidth
			),
			height: max(
				minimumContentHeight,
				bounds.height
			)
		)
		if let content, content.frame != contentFrame
		{
			content.frame = contentFrame
		}
		if let aside
		{
			aside.frame = NSRect(
				x: bounds.maxX - visibleAsideWidth,
				y: bounds.minY,
				width: asideWidth,
				height: max(
					minimumAsideHeight,
					bounds.height
				)
			)
		}
	}
}
