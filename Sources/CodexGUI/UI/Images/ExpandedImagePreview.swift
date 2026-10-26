import AppKit

/// Owns one cancellable expanded image presentation within its initiating window.
@MainActor
final class ExpandedImagePreview
{
	typealias ImageLoader = @Sendable (
		String,
		Int
	) async -> SourceThumbnailLoader.Thumbnail?

	private static let activeOwners = NSMapTable<NSWindow, ExpandedImagePreview>.weakToWeakObjects()

	private(set) var controller: ExpandedImageViewController?
	private(set) var presentationTask: Task<Void, Never>?
	private let loadImage: ImageLoader
	private weak var parent: NSWindow?
	private var resolutionTask: Task<Void, Never>?
	private var teardown: ExpandedImagePresentationTeardown?
	private var generation = 0
	private var requestedResolution = 2048

	init(loadImage: @escaping ImageLoader =
	{
		path, maximumPixelSize in
		await SourceThumbnailLoader.image(
			path: path,
			maximumPixelSize: maximumPixelSize
		)
	})
	{
		self.loadImage = loadImage
	}

	deinit
	{
		presentationTask?.cancel()
		resolutionTask?.cancel()
		let teardown = teardown
		Task
		{
			@MainActor in teardown?.dismiss()
		}
	}

	func present(
		path: String,
		name: String,
		in parent: NSWindow,
		preparedDiagram: NSImage? = nil
	)
	{
		dismiss()
		Self.activeOwners.object(forKey: parent)?.dismiss()
		guard let contentView = parent.contentView
		else
		{
			return
		}
		let backgroundHost = preparedDiagram == nil ? contentView : contentView
			.superview ?? contentView
		let overlayWindow: NSWindow?
		let overlayHost: NSView
		if preparedDiagram != nil
		{
			// AppKit's titlebar may composite above ordinary frame subviews. A child window
			// covers that chrome and receives its input without changing the parent layout.
			let window = ExpandedDiagramOverlayWindow(
				contentRect: parent.frame,
				styleMask: .borderless,
				backing: .buffered,
				defer: false
			)
			window.isReleasedWhenClosed = false
			window.title = "Expanded diagram"
			window.isExcludedFromWindowsMenu = true
			window.isOpaque = false
			window.backgroundColor = .clear
			window.hasShadow = false
			window.level = parent.level
			window.collectionBehavior = [.fullScreenAuxiliary, .transient]
			let host = NSView(frame: NSRect(
				origin: .zero,
				size: parent.frame.size
			))
			window.contentView = host
			overlayWindow = window
			overlayHost = host
		}
		else
		{
			overlayWindow = nil
			overlayHost = contentView
		}
		let hiddenSiblings = backgroundHost.subviews.map
		{
			ExpandedImageAccessibilitySnapshot(view: $0)
		}
		for sibling in hiddenSiblings
		{
			sibling.hide()
		}
		let generation = generation
		let loadImage = loadImage
		let controller = ExpandedImageViewController(name: name)
		self.controller = controller
		self.parent = parent
		Self.activeOwners.setObject(
			self,
			forKey: parent
		)
		if let preparedDiagram
		{
			controller.configureDiagram(
				preparedDiagram,
				appearance: parent.effectiveAppearance
			)
		}
		let previousResponder = parent.firstResponder
		requestedResolution = 2048
		controller.onDismiss =
		{
			[weak self] in self?.dismiss()
		}
		controller.onDetach =
		{
			[weak self] in self?.dismiss()
		}
		controller.onResolutionDemand =
		{
			[weak self] pixels in
			guard preparedDiagram == nil
			else
			{
				return
			}
			self?.requestResolution(
				pixels,
				path: path,
				generation: generation
			)
		}
		controller.view.translatesAutoresizingMaskIntoConstraints = false
		overlayHost.addSubview(
			controller.view,
			positioned: .above,
			relativeTo: nil
		)
		NSLayoutConstraint.activate([
			controller.view.leadingAnchor.constraint(equalTo: overlayHost.leadingAnchor),
			controller.view.trailingAnchor.constraint(equalTo: overlayHost.trailingAnchor),
			controller.view.topAnchor.constraint(equalTo: overlayHost.topAnchor),
			controller.view.bottomAnchor.constraint(equalTo: overlayHost.bottomAnchor)
		])
		overlayHost.layoutSubtreeIfNeeded()
		if let overlayWindow
		{
			parent.addChildWindow(
				overlayWindow,
				ordered: .above
			)
			overlayWindow.makeFirstResponder(controller.view)
			if parent.isVisible
			{
				overlayWindow.makeKeyAndOrderFront(nil)
			}
		}
		else
		{
			parent.makeFirstResponder(controller.view)
		}
		let escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown)
		{
			[weak self, weak parent, weak overlayWindow] event in
			guard let self, let parent,
					event.window === (overlayWindow ?? parent), event.keyCode == 53
			else
			{
				return event
			}
			self.dismiss()
			return nil
		}
		let closeObserver = NotificationCenter.default.addObserver(
			forName: NSWindow.willCloseNotification,
			object: parent,
			queue: .main
		)
		{
			[weak self] _ in
			MainActor.assumeIsolated
			{
				self?.dismiss()
			}
		}
		var geometryObservers: [NSObjectProtocol] = []
		if let overlayWindow
		{
			for notification in [NSWindow.didResizeNotification, NSWindow.didMoveNotification]
			{
				geometryObservers.append(NotificationCenter.default.addObserver(
					forName: notification,
					object: parent,
					queue: .main
				)
				{
					[weak parent, weak overlayWindow] _ in
					MainActor.assumeIsolated
					{
						guard let parent, let overlayWindow
						else
						{
							return
						}
						overlayWindow.setFrame(
							parent.frame,
							display: true
						)
						overlayWindow.contentView?.layoutSubtreeIfNeeded()
					}
				})
			}
		}
		teardown = ExpandedImagePresentationTeardown(
			controller: controller,
			parent: parent,
			previousResponder: previousResponder,
			closeObserver: closeObserver,
			escapeMonitor: escapeMonitor,
			hiddenSiblings: hiddenSiblings,
			overlayWindow: overlayWindow,
			geometryObservers: geometryObservers
		)
		if preparedDiagram != nil
		{
			return
		}
		presentationTask = Task
		{
			[weak self, weak controller, weak parent] in
			let thumbnail = await loadImage(
				path,
				2048
			)
			guard !Task.isCancelled, let self, self.generation == generation,
					let controller, let parent, controller.view.window === parent
			else
			{
				return
			}
			if let thumbnail
			{
				controller.display(thumbnail)
			}
			else
			{
				controller.showLoadFailure()
			}
		}
	}

	func dismiss()
	{
		generation += 1
		presentationTask?.cancel()
		resolutionTask?.cancel()
		presentationTask = nil
		resolutionTask = nil
		if let parent, Self.activeOwners.object(forKey: parent) === self
		{
			Self.activeOwners.removeObject(forKey: parent)
		}
		teardown?.dismiss()
		teardown = nil
		controller = nil
		parent = nil
	}

	func waitForPresentation() async
	{
		await presentationTask?.value
	}

	private func requestResolution(
		_ pixels: Int,
		path: String,
		generation: Int
	)
	{
		guard pixels > requestedResolution, let controller
		else
		{
			return
		}
		requestedResolution = pixels
		resolutionTask?.cancel()
		let loadImage = loadImage
		resolutionTask = Task
		{
			[weak self, weak controller] in
			let thumbnail = await loadImage(
				path,
				pixels
			)
			guard !Task.isCancelled, let self, self.generation == generation,
					let controller, let thumbnail,
					controller.view.window === self.parent
			else
			{
				return
			}
			controller.display(thumbnail)
		}
	}
}

/// Retained teardown can cross the coordinator's nonisolated deinit into a main-actor task.
@MainActor
private final class ExpandedImagePresentationTeardown: @unchecked Sendable
{
	private var controller: ExpandedImageViewController?
	private weak var parent: NSWindow?
	private weak var previousResponder: NSResponder?
	private var closeObserver: NSObjectProtocol?
	private var escapeMonitor: Any?
	private var hiddenSiblings: [ExpandedImageAccessibilitySnapshot]
	private var overlayWindow: NSWindow?
	private var geometryObservers: [NSObjectProtocol]

	init(
		controller: ExpandedImageViewController,
		parent: NSWindow,
		previousResponder: NSResponder?,
		closeObserver: NSObjectProtocol,
		escapeMonitor: Any?,
		hiddenSiblings: [ExpandedImageAccessibilitySnapshot],
		overlayWindow: NSWindow?,
		geometryObservers: [NSObjectProtocol]
	)
	{
		self.controller = controller
		self.parent = parent
		self.previousResponder = previousResponder
		self.closeObserver = closeObserver
		self.escapeMonitor = escapeMonitor
		self.hiddenSiblings = hiddenSiblings
		self.overlayWindow = overlayWindow
		self.geometryObservers = geometryObservers
	}

	func dismiss()
	{
		guard let controller
		else
		{
			return
		}
		if let closeObserver
		{
			NotificationCenter.default.removeObserver(closeObserver)
		}
		if let escapeMonitor
		{
			NSEvent.removeMonitor(escapeMonitor)
		}
		closeObserver = nil
		escapeMonitor = nil
		for observer in geometryObservers
		{
			NotificationCenter.default.removeObserver(observer)
		}
		geometryObservers.removeAll()
		controller.invalidate()
		let presentationWindow = overlayWindow ?? parent
		let ownsFocus = presentationWindow?.firstResponder === controller.view
			|| (presentationWindow?.firstResponder as? NSView)?
			.isDescendant(of: controller.view) == true
		let wasKey = overlayWindow?.isKeyWindow == true
		controller.view.removeFromSuperview()
		if let overlayWindow
		{
			parent?.removeChildWindow(overlayWindow)
			overlayWindow.orderOut(nil)
		}
		overlayWindow = nil
		for sibling in hiddenSiblings
		{
			sibling.restore()
		}
		hiddenSiblings.removeAll()
		self.controller = nil
		if wasKey, parent?.isVisible == true
		{
			parent?.makeKey()
		}
		if ownsFocus, let parent, let previousResponder
		{
			if let responderView = previousResponder as? NSView,
				responderView.window !== parent
			{
				return
			}
			parent.makeFirstResponder(previousResponder)
		}
	}
}

@MainActor
private final class ExpandedDiagramOverlayWindow: NSWindow
{
	override var canBecomeKey: Bool
	{
		true
	}

	override var canBecomeMain: Bool
	{
		false
	}
}

/// Keeps temporary accessibility isolation from retaining the underlying view hierarchy.
@MainActor
private final class ExpandedImageAccessibilitySnapshot
{
	private weak var view: NSView?
	private let wasHidden: Bool

	init(view: NSView)
	{
		self.view = view
		wasHidden = view.isAccessibilityHidden()
	}

	func hide()
	{
		view?.setAccessibilityHidden(true)
	}

	func restore()
	{
		view?.setAccessibilityHidden(wasHidden)
	}
}
