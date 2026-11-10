import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

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
	private var downloadTask: Task<Void, Never>?
	private weak var savePanel: NSSavePanel?
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
		downloadTask?.cancel()
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
		let backgroundHost = contentView.superview ?? contentView
		let overlayWindow: NSWindow?
		let overlayHost: NSView
		do
		{
			// AppKit's titlebar may composite above ordinary frame subviews. A child window
			// covers that chrome and receives its input without changing the parent layout.
			let window = ExpandedImageOverlayWindow(
				contentRect: parent.frame,
				styleMask: .borderless,
				backing: .buffered,
				defer: false
			)
			window.isReleasedWhenClosed = false
			window.title = preparedDiagram == nil ? "Expanded image" : "Expanded diagram"
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
		let hiddenSiblings = backgroundHost.subviews.map
		{
			ExpandedImageAccessibilitySnapshot(view: $0)
		}
		for sibling in hiddenSiblings
		{
			sibling.hide()
		}
		let blurView: ExpandedImageParentBlurView?
		if preparedDiagram == nil
		{
			let blur = ExpandedImageParentBlurView(frame: backgroundHost.bounds)
			blur.autoresizingMask = [.width, .height]
			backgroundHost.addSubview(
				blur,
				positioned: .above,
				relativeTo: nil
			)
			blurView = blur
		}
		else
		{
			blurView = nil
		}
		let generation = generation
		let loadImage = loadImage
		let controller = ExpandedImageViewController(name: name)
		self.controller = controller
		self.parent = parent
		UITestEvidenceRecorder.shared.viewerChanged(controller)
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
		controller.onDownload =
		{
			[weak self] in
			self?.download(
				path: path,
				name: name,
				generation: generation
			)
		}
		if preparedDiagram == nil
		{
			controller.onCopyImage =
			{
				[weak self] in
				Task
				{
					guard let data = await SourceThumbnailLoader.originalData(path: path),
							let self, self.generation == generation, let image = NSImage(data: data)
					else
					{
						return
					}
					NSPasteboard.general.clearContents()
					NSPasteboard.general.writeObjects([image])
				}
			}
			if let owner = parent.windowController as? MainWindowController
			{
				controller.onOpenImage =
				{
					[weak self, weak owner] in
					Task
					{
						guard let data = await SourceThumbnailLoader.originalData(path: path),
								let self, self.generation == generation, let owner,
								let file = Self.exportFile(
								data: data,
								name: name
								)
						else
						{
							return
						}
						self.dismiss()
						owner.openImageInToolTab(
							data: data,
							name: file.name,
							sourceURL: LocalAttachmentURL.resolve(path)
						)
					}
				}
			}
			if let url = LocalAttachmentURL.resolve(path)
			{
				controller.onRevealImage =
				{
					NSWorkspace.shared.activateFileViewerSelecting([url])
				}
			}
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
		let lifetime = DesktopPanelLifetime()
		let appearanceBinding = overlayWindow.map
		{
			DesktopPanelAppearanceBinding(
				panel: $0,
				source: contentView
			)
		}
		lifetime.monitorLocalEvents(matching: .keyDown)
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
		lifetime.addObserver(
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
		if let overlayWindow
		{
			for notification in [NSWindow.didResizeNotification, NSWindow.didMoveNotification]
			{
				lifetime.addObserver(
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
				}
			}
		}
		teardown = ExpandedImagePresentationTeardown(
			controller: controller,
			parent: parent,
			previousResponder: previousResponder,
			lifetime: lifetime,
			appearanceBinding: appearanceBinding,
			hiddenSiblings: hiddenSiblings,
			overlayWindow: overlayWindow,
			blurView: blurView
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
					let controller, let parent, self.parent === parent,
					controller.view.window?.parent === parent
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

	func refreshDiagram(_ image: NSImage)
	{
		guard let controller, let parent
		else
		{
			return
		}
		controller.refreshDiagram(
			image,
			appearance: parent.effectiveAppearance
		)
	}

	func dismiss()
	{
		generation += 1
		presentationTask?.cancel()
		resolutionTask?.cancel()
		downloadTask?.cancel()
		downloadTask = nil
		if let panel = savePanel, let parent = panel.sheetParent
		{
			parent.endSheet(
				panel,
				returnCode: .cancel
			)
		}
		savePanel = nil
		presentationTask = nil
		resolutionTask = nil
		if let parent, Self.activeOwners.object(forKey: parent) === self
		{
			Self.activeOwners.removeObject(forKey: parent)
		}
		if let controller
		{
			UITestEvidenceRecorder.shared.viewerChanged(
				controller,
				active: false
			)
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

	private func download(
		path: String,
		name: String,
		generation: Int
	)
	{
		guard downloadTask == nil, savePanel?.sheetParent == nil
		else
		{
			return
		}
		downloadTask = Task
		{
			[weak self] in
			defer
			{
				if self?.generation == generation
				{
					self?.downloadTask = nil
				}
			}
			guard let data = await SourceThumbnailLoader.originalData(path: path),
					!Task.isCancelled, let self, self.generation == generation,
					let window = self.controller?.view.window,
					let file = Self.exportFile(
					data: data,
					name: name
					)
			else
			{
				return
			}
			self.savePanel = MarkdownDiagramExport.save(
				file,
				in: window
			)
		}
	}

	static func exportFile(
		data: Data,
		name: String
	) -> MarkdownDiagramExport.File?
	{
		guard let source = CGImageSourceCreateWithData(
			data as CFData,
			nil
		),
			let identifier = CGImageSourceGetType(source) as String?,
			let type = UTType(identifier), type.conforms(to: .image)
		else
		{
			return nil
		}
		let proposed = URL(fileURLWithPath: name).lastPathComponent
		let base = proposed.isEmpty || proposed == "." || proposed == ".." ? "Image" : proposed
		let url = URL(fileURLWithPath: base)
		let suppliedType = UTType(filenameExtension: url.pathExtension)
		let fileName: String
		if let suppliedType, suppliedType.conforms(to: type)
		{
			fileName = base
		}
		else if let ext = type.preferredFilenameExtension
		{
			let stem = url.pathExtension.isEmpty ? base : url.deletingPathExtension()
				.lastPathComponent
			fileName = "\(stem).\(ext)"
		}
		else
		{
			fileName = base
		}
		return MarkdownDiagramExport.File(
			data: data,
			contentType: type,
			name: fileName
		)
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
					controller.view.window?.parent === self.parent
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
	private let lifetime: DesktopPanelLifetime
	private let appearanceBinding: DesktopPanelAppearanceBinding?
	private var hiddenSiblings: [ExpandedImageAccessibilitySnapshot]
	private var overlayWindow: NSWindow?
	private var blurView: NSView?

	init(
		controller: ExpandedImageViewController,
		parent: NSWindow,
		previousResponder: NSResponder?,
		lifetime: DesktopPanelLifetime,
		appearanceBinding: DesktopPanelAppearanceBinding?,
		hiddenSiblings: [ExpandedImageAccessibilitySnapshot],
		overlayWindow: NSWindow?,
		blurView: NSView?
	)
	{
		self.blurView = blurView
		self.controller = controller
		self.parent = parent
		self.previousResponder = previousResponder
		self.lifetime = lifetime
		self.appearanceBinding = appearanceBinding
		self.hiddenSiblings = hiddenSiblings
		self.overlayWindow = overlayWindow
	}

	func dismiss()
	{
		guard let controller
		else
		{
			return
		}
		lifetime.invalidate()
		appearanceBinding?.invalidate()
		controller.invalidate()
		let presentationWindow = overlayWindow ?? parent
		if let sheet = presentationWindow?.attachedSheet
		{
			presentationWindow?.endSheet(
				sheet,
				returnCode: .cancel
			)
		}
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
		blurView?.removeFromSuperview()
		blurView = nil
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
private final class ExpandedImageOverlayWindow: NSWindow
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

/// A background filter samples its parent layer tree, so it lives beneath the child viewer.
/// Input, focus and accessibility remain with the child presentation.
@MainActor
private final class ExpandedImageParentBlurView: NSView
{
	override init(frame: NSRect)
	{
		super.init(frame: frame)
		wantsLayer = true
		let blur = CIFilter(name: "CIGaussianBlur")!
		blur.setValue(
			1,
			forKey: kCIInputRadiusKey
		)
		backgroundFilters = [blur]
		setAccessibilityHidden(true)
		setAccessibilityIdentifier("expanded-image-blur")
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func hitTest(_ point: NSPoint) -> NSView?
	{
		nil
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
