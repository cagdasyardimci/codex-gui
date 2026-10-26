import AppKit

/// A window-content overlay; 100% maps each original image pixel to one layout point.
@MainActor
final class ExpandedImageViewController: NSViewController
{
	let backdropView: NSVisualEffectView = ExpandedImageVisualEffectView()
	let scrollView = NSScrollView()
	let zoomButton = ExpandedImageZoomButton(
		frame: .zero,
		pullsDown: false
	)
	let closeButton = ExpandedImageCloseButton()
	let imageView = NSImageView()
	private(set) var originalPixelSize = NSSize.zero
	var onDismiss: (() -> Void)?
	var onResolutionDemand: ((Int) -> Void)?
	var onDetach: (() -> Void)?

	private let statusLabel = NSTextField(labelWithString: "Loading image…")
	private let dimmingView = ExpandedImageDimmingView()
	private var diagramImage: NSImage?
	private var diagramZoomLabel: NSTextField?
	private var diagramZoomOutButton: NSButton?
	private var diagramZoomInButton: NSButton?
	private static let diagramZoomStops = [
		25,
		33,
		50,
		67,
		75,
		80,
		90,
		100,
		110,
		125,
		150,
		175,
		200,
		250,
		300,
		400,
		500
	]
	private var fitting = true
	private var updatingGeometry = false
	private var backingScale: CGFloat = 1
	private var boundsObserver: NSObjectProtocol?
	private var magnificationObserver: NSObjectProtocol?

	var displayedZoomPercentage: Int
	{
		Int((scrollView.magnification * 100).rounded())
	}

	init(name: String)
	{
		super.init(
			nibName: nil,
			bundle: nil
		)
		_ = view
		imageView.setAccessibilityLabel("Attached image: \(name)")
	}

	@available(
		*,
		unavailable
	)
	required init?(coder: NSCoder)
	{
		fatalError("init(coder:) has not been implemented")
	}

	override func loadView()
	{
		let overlay = ExpandedImageOverlayView()
		overlay.onLayout =
		{
			[weak self] in self?.updateGeometry()
		}
		overlay.onDismiss =
		{
			[weak self] in self?.onDismiss?()
		}
		overlay.onDetach =
		{
			[weak self] in self?.onDetach?()
		}
		overlay.setAccessibilityElement(true)
		overlay.setAccessibilityRole(.group)
		overlay.setAccessibilityIdentifier("expanded-image-preview")
		overlay.setAccessibilityLabel("Expanded image viewer")
		view = overlay
		view.appearance = NSAppearance(named: .darkAqua)

		backdropView.material = .fullScreenUI
		backdropView.blendingMode = .withinWindow
		backdropView.state = .active
		// Blend original content with the native blur to keep the conversation distinguishable.
		backdropView.alphaValue = 0.8
		backdropView.isEmphasized = false
		backdropView.setAccessibilityHidden(true)
		backdropView.setAccessibilityIdentifier("expanded-image-blur")
		dimmingView.setAccessibilityHidden(true)
		dimmingView.setAccessibilityIdentifier("expanded-image-dimming")
		for background in [backdropView, dimmingView]
		{
			background.translatesAutoresizingMaskIntoConstraints = false
			view.addSubview(background)
			NSLayoutConstraint.activate([
				background.leadingAnchor.constraint(equalTo: view.leadingAnchor),
				background.trailingAnchor.constraint(equalTo: view.trailingAnchor),
				background.topAnchor.constraint(equalTo: view.topAnchor),
				background.bottomAnchor.constraint(equalTo: view.bottomAnchor)
			])
		}

		scrollView.drawsBackground = false
		scrollView.borderType = .noBorder
		scrollView.hasHorizontalScroller = true
		scrollView.hasVerticalScroller = true
		scrollView.autohidesScrollers = true
		scrollView.allowsMagnification = true
		scrollView.minMagnification = 0.01
		scrollView.maxMagnification = 8
		scrollView.contentView = ExpandedImageClipView()
		scrollView.contentView.drawsBackground = false
		scrollView.contentView.postsBoundsChangedNotifications = true
		imageView.imageScaling = .scaleAxesIndependently
		scrollView.documentView = imageView

		zoomButton.isBordered = false
		zoomButton.focusRingType = .none
		zoomButton.target = self
		zoomButton.action = #selector(selectZoom(_:))
		let zoomMenu = NSMenu()
		zoomMenu.autoenablesItems = false
		for (title, tag) in [
			("100%", 0),
			("Fit", -1),
			("Actual Size", -2),
			("25%", 25),
			("50%", 50),
			("100%", 100),
			("200%", 200),
			("400%", 400)
		]
		{
			let item = NSMenuItem(
				title: title,
				action: nil,
				keyEquivalent: ""
			)
			item.tag = tag
			item.isEnabled = tag != 0
			zoomMenu.addItem(item)
		}
		zoomButton.menu = zoomMenu
		zoomButton.selectItem(withTag: 0)
		zoomButton.setAccessibilityLabel("Image zoom")
		zoomButton.setAccessibilityIdentifier("expanded-image-zoom")

		closeButton.image = NSImage(
			systemSymbolName: "xmark",
			accessibilityDescription: "Close image"
		)
		closeButton.bezelStyle = .circular
		closeButton.isBordered = false
		closeButton.focusRingType = .none
		closeButton.target = self
		closeButton.action = #selector(closeImage(_:))
		closeButton.setAccessibilityLabel("Close image")
		closeButton.setAccessibilityIdentifier("expanded-image-close")
		overlay.nextKeyView = zoomButton
		zoomButton.nextKeyView = closeButton
		closeButton.nextKeyView = zoomButton
		statusLabel.textColor = .white
		statusLabel.alignment = .center

		for child in [scrollView, zoomButton, closeButton, statusLabel]
		{
			child.translatesAutoresizingMaskIntoConstraints = false
			view.addSubview(child)
		}
		NSLayoutConstraint.activate([
			closeButton.topAnchor.constraint(
				equalTo: view.topAnchor,
				constant: 12
			),
			closeButton.trailingAnchor.constraint(
				equalTo: view.trailingAnchor,
				constant: -16
			),
			closeButton.widthAnchor.constraint(equalToConstant: 32),
			closeButton.heightAnchor.constraint(equalToConstant: 32),
			zoomButton.widthAnchor.constraint(equalToConstant: 64),
			zoomButton.heightAnchor.constraint(equalToConstant: 32),
			zoomButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
			zoomButton.trailingAnchor.constraint(
				equalTo: closeButton.leadingAnchor,
				constant: -10
			),
			scrollView.topAnchor.constraint(
				equalTo: closeButton.bottomAnchor,
				constant: 14
			),
			scrollView.leadingAnchor.constraint(
				equalTo: view.leadingAnchor,
				constant: 68
			),
			scrollView.trailingAnchor.constraint(
				equalTo: view.trailingAnchor,
				constant: -68
			),
			scrollView.bottomAnchor.constraint(
				equalTo: view.bottomAnchor,
				constant: -82
			),
			statusLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
			statusLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
		])
		boundsObserver = NotificationCenter.default.addObserver(
			forName: NSView.boundsDidChangeNotification,
			object: scrollView.contentView,
			queue: .main
		)
		{
			[weak self] _ in
			MainActor.assumeIsolated
			{
				self?.zoomDidChange()
			}
		}
		magnificationObserver = NotificationCenter.default.addObserver(
			forName: NSScrollView.willStartLiveMagnifyNotification,
			object: scrollView,
			queue: .main
		)
		{
			[weak self] _ in
			MainActor.assumeIsolated
			{
				self?.fitting = false
			}
		}
	}

	func configureDiagram(
		_ image: NSImage,
		appearance: NSAppearance
	)
	{
		diagramImage = image
		backdropView.isHidden = true
		dimmingView.fillOpacity = 0.9
		scrollView.minMagnification = 0.25
		scrollView.maxMagnification = 5
		scrollView.appearance = appearance
		view.setAccessibilityLabel("Expanded diagram viewer")
		imageView.setAccessibilityLabel("Mermaid diagram")
		closeButton.setAccessibilityLabel("Close diagram")
		closeButton.toolTip = "Close diagram"
		closeButton.usesLightSurface = true
		for constraint in closeButton.constraints where
			constraint.firstAttribute == .width || constraint.firstAttribute == .height
		{
			constraint.constant = constraint.firstAttribute == .width ? 42 : 40
		}
		for constraint in view.constraints where
			(constraint.firstItem as? NSView) === closeButton && constraint
			.firstAttribute == .trailing
		{
			constraint.constant = -12
		}
		statusLabel.isHidden = true
		zoomButton.isHidden = true
		NSLayoutConstraint.deactivate(view.constraints.filter
		{
			($0.firstItem as? NSView) === zoomButton
				|| ($0.firstItem as? NSView) === scrollView
		})
		scrollView.drawsBackground = true
		scrollView.backgroundColor = .textBackgroundColor
		scrollView.contentView.drawsBackground = true
		scrollView.contentView.backgroundColor = .textBackgroundColor
		scrollView.wantsLayer = true
		scrollView.layer?.masksToBounds = true
		let canvas = NSView()
		canvas.translatesAutoresizingMaskIntoConstraints = false
		canvas.appearance = appearance
		canvas.wantsLayer = true
		appearance.performAsCurrentDrawingAppearance
		{
			canvas.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
		}
		canvas.layer?.cornerRadius = 20
		canvas.layer?.masksToBounds = true
		canvas.setAccessibilityIdentifier("expanded-diagram-canvas")
		scrollView.removeFromSuperview()
		view.addSubview(
			canvas,
			positioned: .below,
			relativeTo: closeButton
		)
		canvas.addSubview(scrollView)
		let download = ExpandedImageDownloadButton(
			image: NSImage(
				systemSymbolName: "arrow.down.to.line",
				accessibilityDescription: nil
			)!,
			target: self,
			action: #selector(downloadDiagram(_:))
		)
		download.bezelStyle = .circular
		download.isBordered = false
		download.contentTintColor = .darkGray
		download.wantsLayer = true
		download.layer?.backgroundColor = NSColor.white.cgColor
		download.layer?.cornerRadius = 20
		download.appearance = NSAppearance(named: .aqua)
		download.setAccessibilityLabel("Download image")
		download.toolTip = "Download image"
		let minus = ExpandedImageDownloadButton(
			title: "−",
			target: self,
			action: #selector(zoomDiagramOut(_:))
		)
		let plus = ExpandedImageDownloadButton(
			title: "+",
			target: self,
			action: #selector(zoomDiagramIn(_:))
		)
		for button in [minus, plus]
		{
			button.bezelStyle = .circular
			button.font = NSFont.systemFont(ofSize: 20)
			button.widthAnchor.constraint(equalToConstant: 36).isActive = true
			button.heightAnchor.constraint(equalToConstant: 36).isActive = true
		}
		diagramZoomOutButton = minus
		diagramZoomInButton = plus
		minus.setAccessibilityLabel("Zoom out")
		plus.setAccessibilityLabel("Zoom in")
		let label = NSTextField(labelWithString: "100%")
		label.alignment = .center
		label.setAccessibilityLabel("Diagram zoom percentage")
		diagramZoomLabel = label
		let zoom = NSStackView(views: [minus, label, plus])
		zoom.orientation = .horizontal
		zoom.spacing = 4
		zoom.edgeInsets = NSEdgeInsets(
			top: 4,
			left: 4,
			bottom: 4,
			right: 4
		)
		zoom.wantsLayer = true
		zoom.layer?.cornerRadius = 22
		zoom.layer?.backgroundColor = NSColor.white.cgColor
		zoom.appearance = NSAppearance(named: .aqua)
		for child in [download, zoom]
		{
			child.translatesAutoresizingMaskIntoConstraints = false
			view.addSubview(child)
		}
		NSLayoutConstraint.activate([
			download.trailingAnchor.constraint(
				equalTo: closeButton.leadingAnchor,
				constant: -8
			),
			download.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
			download.widthAnchor.constraint(equalToConstant: 40),
			download.heightAnchor.constraint(equalToConstant: 40),
			canvas.topAnchor.constraint(
				equalTo: view.topAnchor,
				constant: 48
			),
			canvas.leadingAnchor.constraint(
				equalTo: view.leadingAnchor,
				constant: 32
			),
			canvas.trailingAnchor.constraint(
				equalTo: view.trailingAnchor,
				constant: -32
			),
			canvas.bottomAnchor.constraint(
				equalTo: view.bottomAnchor,
				constant: -96
			),
			scrollView.topAnchor.constraint(
				equalTo: canvas.topAnchor,
				constant: 16
			),
			scrollView.leadingAnchor.constraint(
				equalTo: canvas.leadingAnchor,
				constant: 16
			),
			scrollView.trailingAnchor.constraint(
				equalTo: canvas.trailingAnchor,
				constant: -16
			),
			scrollView.bottomAnchor.constraint(
				equalTo: canvas.bottomAnchor,
				constant: -16
			),
			zoom.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			zoom.bottomAnchor.constraint(
				equalTo: view.bottomAnchor,
				constant: -32
			),
			label.widthAnchor.constraint(equalToConstant: 64)
		])
		view.nextKeyView = download
		download.nextKeyView = closeButton
		closeButton.nextKeyView = minus
		minus.nextKeyView = plus
		plus.nextKeyView = download
		originalPixelSize = image.size
		imageView.image = image
		updateGeometry()
	}

	@objc private func downloadDiagram(_ sender: Any?)
	{
		guard let diagramImage, let window = view.window
		else
		{
			return
		}
		MarkdownDiagramExport.save(
			diagramImage,
			in: window
		)
	}

	@objc private func zoomDiagramOut(_ sender: Any?)
	{
		let percentage = scrollView.magnification * 100
		let stop = Self.diagramZoomStops.last
		{
			CGFloat($0) < percentage - 0.0001
		} ?? 25
		setZoom(CGFloat(stop) / 100)
	}

	@objc private func zoomDiagramIn(_ sender: Any?)
	{
		let percentage = scrollView.magnification * 100
		let stop = Self.diagramZoomStops.first
		{
			CGFloat($0) > percentage + 0.0001
		} ?? 500
		setZoom(CGFloat(stop) / 100)
	}

	func display(_ thumbnail: SourceThumbnailLoader.Thumbnail)
	{
		originalPixelSize = thumbnail.originalPixelSize
		imageView.image = NSImage(
			cgImage: thumbnail.image,
			size: originalPixelSize
		)
		statusLabel.isHidden = true
		updateGeometry()
	}

	func showLoadFailure()
	{
		statusLabel.stringValue = "Unable to load image"
		zoomButton.isEnabled = false
	}

	func fitImage()
	{
		fitting = true
		updateGeometry()
	}

	func showActualSize()
	{
		setZoom(1)
	}

	func setZoom(_ magnification: CGFloat)
	{
		guard originalPixelSize.width > 0
		else
		{
			return
		}
		fitting = false
		applyMagnification(magnification)
	}

	func invalidate()
	{
		if let boundsObserver
		{
			NotificationCenter.default.removeObserver(boundsObserver)
		}
		if let magnificationObserver
		{
			NotificationCenter.default.removeObserver(magnificationObserver)
		}
		boundsObserver = nil
		magnificationObserver = nil
		onDismiss = nil
		onDetach = nil
		onResolutionDemand = nil
	}

	override func cancelOperation(_ sender: Any?)
	{
		onDismiss?()
	}

	private func updateGeometry()
	{
		// The diagram canvas adds a layout level between the overlay and its viewport.
		if let canvas = scrollView.superview, canvas !== view
		{
			canvas.layoutSubtreeIfNeeded()
		}
		guard !updatingGeometry, originalPixelSize.width > 0,
				scrollView.bounds.width > 0, scrollView.bounds.height > 0
		else
		{
			return
		}
		updatingGeometry = true
		backingScale = view.window?.backingScaleFactor ?? 1
		let imageSize = originalPixelSize
		if imageView.frame.size != imageSize
		{
			imageView.frame = NSRect(
				origin: .zero,
				size: imageSize
			)
		}
		if fitting
		{
			let viewport = scrollView.contentSize
			let fit = min(
				viewport.width / imageView.frame.width,
				viewport.height / imageView.frame.height
			)
			if diagramImage == nil
			{
				scrollView.minMagnification = min(
					0.01,
					fit
				)
			}
			applyMagnification(min(
				1,
				fit
			))
		}
		else
		{
			scrollView.contentView.setBoundsOrigin(scrollView.contentView.bounds.origin)
		}
		updatingGeometry = false
		zoomDidChange()
	}

	private func applyMagnification(_ value: CGFloat)
	{
		let center = NSPoint(
			x: imageView.bounds.midX,
			y: imageView.bounds.midY
		)
		scrollView.setMagnification(
			min(
				scrollView.maxMagnification,
				max(
					scrollView.minMagnification,
					value
				)
			),
			centeredAt: center
		)
		zoomDidChange()
	}

	private func zoomDidChange()
	{
		diagramZoomLabel?.stringValue = "\(displayedZoomPercentage)%"
		diagramZoomOutButton?.isEnabled = scrollView.magnification > 0.250001
		diagramZoomInButton?.isEnabled = scrollView.magnification < 4.999999
		zoomButton.menu?.item(withTag: 0)?.title = "\(displayedZoomPercentage)%"
		zoomButton.selectItem(withTag: 0)
		zoomButton.needsDisplay = true
		guard originalPixelSize.width > 0
		else
		{
			return
		}
		let pixels = max(
			originalPixelSize.width,
			originalPixelSize.height
		) * scrollView
			.magnification * backingScale
		onResolutionDemand?(Int(min(
			8192,
			max(
				2048,
				ceil(pixels)
			)
		)))
	}

	@objc private func selectZoom(_ sender: NSPopUpButton)
	{
		switch sender.selectedItem?.tag
		{
		case -1: fitImage()
		case -2: showActualSize()
		case 25: setZoom(0.25)
		case 50: setZoom(0.5)
		case 100: setZoom(1)
		case 200: setZoom(2)
		case 400: setZoom(4)
		default: break
		}
	}

	@objc private func closeImage(_ sender: NSButton)
	{
		onDismiss?()
	}
}

@MainActor
private final class ExpandedImageOverlayView: NSView
{
	var onLayout: (() -> Void)?
	var onDismiss: (() -> Void)?
	var onDetach: (() -> Void)?
	private var wasAttached = false
	override var acceptsFirstResponder: Bool
	{
		true
	}

	override func layout()
	{
		super.layout()
		onLayout?()
	}

	override func viewDidChangeBackingProperties()
	{
		super.viewDidChangeBackingProperties()
		onLayout?()
	}

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		if window != nil
		{
			wasAttached = true
		}
		else if wasAttached
		{
			onDetach?()
		}
	}

	override func cancelOperation(_ sender: Any?)
	{
		onDismiss?()
	}
	override func keyDown(with event: NSEvent)
	{
		if event.keyCode == 53
		{
			onDismiss?()
		}
		else if event.keyCode == 48
		{
			if event.modifierFlags.contains(.shift)
			{
				window?.selectPreviousKeyView(nil)
			}
			else
			{
				window?.selectNextKeyView(nil)
			}
		}
	}

	override func mouseDown(with event: NSEvent)
	{
	}
}

@MainActor
private final class ExpandedImageClipView: NSClipView
{
	override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect
	{
		var result = super.constrainBoundsRect(proposedBounds)
		guard let documentView
		else
		{
			return result
		}
		if documentView.frame.width < result.width
		{
			result.origin.x = (documentView.frame.width - result.width) / 2
		}
		if documentView.frame.height < result.height
		{
			result.origin.y = (documentView.frame.height - result.height) / 2
		}
		return result
	}
}

/// Decorative backdrop layers never intercept the overlay's input handling.
@MainActor
private final class ExpandedImageVisualEffectView: NSVisualEffectView
{
	override func hitTest(_ point: NSPoint) -> NSView?
	{
		nil
	}
}

@MainActor
private final class ExpandedImageDimmingView: NSView
{
	var fillOpacity: CGFloat = 0.5
	{
		didSet
		{
			needsDisplay = true
		}
	}

	override func draw(_ dirtyRect: NSRect)
	{
		NSColor.black.withAlphaComponent(fillOpacity).setFill()
		dirtyRect.fill()
	}

	override func hitTest(_ point: NSPoint) -> NSView?
	{
		nil
	}
}
