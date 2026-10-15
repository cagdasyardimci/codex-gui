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
		in parent: NSWindow
	)
	{
		dismiss()
		Self.activeOwners.object(forKey: parent)?.dismiss()
		guard let contentView = parent.contentView
		else
		{
			return
		}
		let hiddenSiblings = contentView.subviews.map
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
			self?.requestResolution(
				pixels,
				path: path,
				generation: generation
			)
		}
		controller.view.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(
			controller.view,
			positioned: .above,
			relativeTo: nil
		)
		NSLayoutConstraint.activate([
			controller.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			controller.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			controller.view.topAnchor.constraint(equalTo: contentView.topAnchor),
			controller.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
		])
		contentView.layoutSubtreeIfNeeded()
		parent.makeFirstResponder(controller.view)
		let escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown)
		{
			[weak self, weak parent] event in
			guard let self, let parent, event.window === parent, event.keyCode == 53
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
		teardown = ExpandedImagePresentationTeardown(
			controller: controller,
			parent: parent,
			previousResponder: previousResponder,
			closeObserver: closeObserver,
			escapeMonitor: escapeMonitor,
			hiddenSiblings: hiddenSiblings
		)
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

	init(
		controller: ExpandedImageViewController,
		parent: NSWindow,
		previousResponder: NSResponder?,
		closeObserver: NSObjectProtocol,
		escapeMonitor: Any?,
		hiddenSiblings: [ExpandedImageAccessibilitySnapshot]
	)
	{
		self.controller = controller
		self.parent = parent
		self.previousResponder = previousResponder
		self.closeObserver = closeObserver
		self.escapeMonitor = escapeMonitor
		self.hiddenSiblings = hiddenSiblings
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
		controller.invalidate()
		let ownsFocus = parent?.firstResponder === controller.view
			|| (parent?.firstResponder as? NSView)?.isDescendant(of: controller.view) == true
		controller.view.removeFromSuperview()
		for sibling in hiddenSiblings
		{
			sibling.restore()
		}
		hiddenSiblings.removeAll()
		self.controller = nil
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
