import AppKit
import CoreImage

@MainActor
final class RemotePairingPanelController: NSWindowController
{
	var onClose: (() -> Void)?
	var onRefresh: (() -> Void)?
	private let qr = RemotePairingQRView()
	private(set) var fullscreen: RemotePairingPanel?
	private weak var presentationHost: NSWindow?
	private weak var previousResponder: NSResponder?
	private let lifetime = DesktopPanelLifetime()
	private var dimmer: NSWindow?
	private var refreshButtonReference: NSButton?
	private var expandButtonReference: NSButton?
	private var copyButtonReference: NSButton?
	private var phoneButton: RemoteConnectionsButton?
	private var computerButton: RemoteConnectionsButton?
	private var pairingFrameHeight: NSLayoutConstraint?
	private var computerInstructions: NSTextField?
	private let manualCode = NSTextField(labelWithString: "")
	private let copyPasteboard: NSPasteboard
	private let loading = NSProgressIndicator()
	private enum DeviceMode
	{
		case phone
		case computer
	}
	private var deviceMode = DeviceMode.phone
	private var isPending = false

	init(pasteboard: NSPasteboard = .general)
	{
		copyPasteboard = pasteboard
		let panel = RemotePairingPanel(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: LayoutTokens.Connections.modalWidth,
				height: LayoutTokens.Connections.modalHeight
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		panel.isReleasedWhenClosed = false
		panel.isOpaque = false
		panel.backgroundColor = .clear
		panel.hasShadow = true
		panel.contentMinSize = NSSize(
			width: LayoutTokens.Connections.modalWidth,
			height: LayoutTokens.Connections.modalHeight
		)
		panel.contentMaxSize = NSSize(
			width: LayoutTokens.Connections.modalWidth,
			height: LayoutTokens.Connections.computerModalHeight
		)
		super.init(window: panel)
		panel.onCancel =
		{
			[weak self] in self?.onClose?()
		}
		configure()
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	private func configure()
	{
		guard let content = window?.contentView
		else
		{
			return
		}
		// AppKit sizes a borderless panel from the content view's fitting width.
		content.widthAnchor.constraint(
			equalToConstant: LayoutTokens.Connections.modalWidth
		).isActive = true
		content.wantsLayer = true
		let mask = CAShapeLayer()
		mask.path = AppKitShapePath.roundedCGPath(
			content.bounds,
			radius: ShapeTokens.Connections.modalRadius,
			curve: ShapeTokens.Connections.curve
		)
		content.layer?.mask = mask
		content.layer?.masksToBounds = true
		let background = NSVisualEffectView()
		background.material = .popover
		background.blendingMode = .behindWindow
		background.state = .active
		background.translatesAutoresizingMaskIntoConstraints = false
		content.addSubview(background)
		NSLayoutConstraint.activate([
			background.leadingAnchor.constraint(equalTo: content.leadingAnchor),
			background.trailingAnchor.constraint(equalTo: content.trailingAnchor),
			background.topAnchor.constraint(equalTo: content.topAnchor),
			background.bottomAnchor.constraint(equalTo: content.bottomAnchor),
		])
		let artwork = RemotePairingArtworkView()
		artwork.translatesAutoresizingMaskIntoConstraints = false
		content.addSubview(artwork)
		NSLayoutConstraint.activate([
			artwork.leadingAnchor.constraint(equalTo: content.leadingAnchor),
			artwork.trailingAnchor.constraint(equalTo: content.trailingAnchor),
			artwork.topAnchor.constraint(equalTo: content.topAnchor),
			artwork.heightAnchor.constraint(
				equalToConstant: LayoutTokens.Connections.modalArtworkHeight
			),
		])
		let close = icon(
			.closeBold,
			label: "Close",
			action: #selector(closePairing)
		)
		content.addSubview(close)
		let title = NSTextField(wrappingLabelWithString:
			"Approve on your device to control this Mac remotely")
		title.font = AppKitFontResolver.font(TypographyTokens.Connections.modalTitle)
		title.alignment = .center
		let phone = RemoteConnectionsButton(
			title: "Phone",
			presentation: .pairingTab(selected: true)
		)
		phone.target = self
		phone.action = #selector(showPhone)
		phone.setAccessibilityValue("On")
		phoneButton = phone
		window?.initialFirstResponder = phone
		let computer = RemoteConnectionsButton(
			title: "Computer",
			presentation: .pairingTab(selected: false)
		)
		computer.target = self
		computer.action = #selector(showComputer)
		computer.setAccessibilityValue("Off")
		computerButton = computer
		let segments = AppKitLayout.horizontalStack(
			[phone, computer],
			spacing: 2
		)
		segments.distribution = .fillEqually
		let segmentTrack = RemotePairingSegmentTrack()
		segmentTrack.addSubview(segments)
		segments.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			segments.leadingAnchor.constraint(
				equalTo: segmentTrack.leadingAnchor,
				constant: 4
			),
			segments.trailingAnchor.constraint(
				equalTo: segmentTrack.trailingAnchor,
				constant: -4
			),
			segments.topAnchor.constraint(
				equalTo: segmentTrack.topAnchor,
				constant: 4
			),
			segments.bottomAnchor.constraint(
				equalTo: segmentTrack.bottomAnchor,
				constant: -4
			),
		])
		let frame = RemoteConnectionsCard()
		frame.isPairingFrame = true
		qr.setAccessibilityElement(true)
		qr.setAccessibilityLabel("Remote connection pairing QR code")
		qr.translatesAutoresizingMaskIntoConstraints = false
		frame.addSubview(qr)
		manualCode.font = NSFont.systemFont(
			ofSize: 36,
			weight: .semibold
		)
		manualCode.alignment = .center
		manualCode.textColor = AppKitColorTokens.settingsPrimaryText
		manualCode.isHidden = true
		manualCode.setAccessibilityLabel("Manual pairing code")
		manualCode.translatesAutoresizingMaskIntoConstraints = false
		frame.addSubview(manualCode)
		NSLayoutConstraint.activate([
			manualCode.centerXAnchor.constraint(equalTo: frame.centerXAnchor),
			manualCode.centerYAnchor.constraint(equalTo: frame.centerYAnchor),
			manualCode.leadingAnchor.constraint(greaterThanOrEqualTo: frame.leadingAnchor),
			manualCode.trailingAnchor.constraint(lessThanOrEqualTo: frame.trailingAnchor),
		])
		loading.style = .spinning
		loading.isDisplayedWhenStopped = false
		loading.translatesAutoresizingMaskIntoConstraints = false
		frame.addSubview(loading)
		NSLayoutConstraint.activate([
			loading.centerXAnchor.constraint(equalTo: frame.centerXAnchor),
			loading.centerYAnchor.constraint(equalTo: frame.centerYAnchor),
		])
		let expand = icon(
			.expand,
			label: "Show QR code fullscreen",
			action: #selector(expandQR)
		)
		let refresh = icon(
			.regenerate,
			label: "Refresh pairing code",
			action: #selector(refreshQR)
		)
		let copy = icon(
			.copy,
			label: "Copy pairing code",
			action: #selector(copyCode)
		)
		copy.isHidden = true
		copy.isEnabled = false
		frame.addSubview(copy)
		copyButtonReference = copy
		frame.addSubview(expand)
		expandButtonReference = expand
		frame.addSubview(refresh)
		refreshButtonReference = refresh
		let instructions = NSTextField(wrappingLabelWithString:
			"On your other computer, open ChatGPT Settings > Connections > "
				+ "Control other devices, then enter this code.")
		instructions.font = AppKitFontResolver.font(TypographyTokens.Connections.caption)
		instructions.textColor = AppKitColorTokens.settingsSecondaryText
		instructions.alignment = .center
		instructions.isHidden = true
		computerInstructions = instructions
		let body = AppKitLayout.verticalStack(
			[title, segmentTrack, frame, instructions],
			spacing: 24
		)
		body.detachesHiddenViews = true
		body.setCustomSpacing(
			16,
			after: segmentTrack
		)
		body.setCustomSpacing(
			16,
			after: frame
		)
		body.translatesAutoresizingMaskIntoConstraints = false
		content.addSubview(body)
		let frameHeight = frame.heightAnchor.constraint(equalToConstant: 248)
		pairingFrameHeight = frameHeight
		NSLayoutConstraint.activate([
			close.topAnchor.constraint(
				equalTo: content.topAnchor,
				constant: 16
			),
			close.trailingAnchor.constraint(
				equalTo: content.trailingAnchor,
				constant: -16
			),
			body.topAnchor.constraint(
				equalTo: artwork.bottomAnchor,
				constant: 24
			),
			body.leadingAnchor.constraint(
				equalTo: content.leadingAnchor,
				constant: 24
			),
			body.trailingAnchor.constraint(
				equalTo: content.trailingAnchor,
				constant: -24
			),
			title.widthAnchor.constraint(equalTo: body.widthAnchor),
			segmentTrack.widthAnchor.constraint(equalTo: body.widthAnchor),
			segmentTrack.heightAnchor.constraint(equalToConstant: 36),
			frame.widthAnchor.constraint(equalTo: body.widthAnchor),
			frameHeight,
			instructions.widthAnchor.constraint(equalTo: body.widthAnchor),
			instructions.heightAnchor.constraint(equalToConstant: 39),
			qr.centerXAnchor.constraint(equalTo: frame.centerXAnchor),
			qr.centerYAnchor.constraint(equalTo: frame.centerYAnchor),
			qr.widthAnchor.constraint(equalToConstant: LayoutTokens.Connections.qrSize),
			qr.heightAnchor.constraint(equalTo: qr.widthAnchor),
			refresh.trailingAnchor.constraint(
				equalTo: frame.trailingAnchor,
				constant: -12
			),
			refresh.bottomAnchor.constraint(
				equalTo: frame.bottomAnchor,
				constant: -12
			),
			expand.trailingAnchor.constraint(
				equalTo: refresh.leadingAnchor,
				constant: -4
			),
			expand.bottomAnchor.constraint(equalTo: refresh.bottomAnchor),
			copy.trailingAnchor.constraint(
				equalTo: refresh.leadingAnchor,
				constant: -4
			),
			copy.bottomAnchor.constraint(equalTo: refresh.bottomAnchor),
		])
	}

	private func icon(
		_ icon: DesktopIcon,
		label: String,
		action: Selector
	) -> NSButton
	{
		let button = RemotePairingIconButton(
			icon: icon,
			label: label,
			target: self,
			action: action
		)
		return button
	}

	func present(over host: NSWindow)
	{
		guard let window
		else
		{
			return
		}
		presentationHost = host
		previousResponder = host.firstResponder
		for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification]
		{
			lifetime.addObserver(
				forName: name,
				object: host,
				queue: .main
			)
			{
				[weak self] _ in
				MainActor.assumeIsolated
				{
					self?.updatePresentationGeometry()
				}
			}
		}
		let dimmer = NSWindow(
			contentRect: host.frame,
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		dimmer.backgroundColor = NSColor.black.withAlphaComponent(0.3)
		dimmer.isReleasedWhenClosed = false
		dimmer.isOpaque = false
		dimmer.ignoresMouseEvents = true
		host.addChildWindow(
			dimmer,
			ordered: .above
		)
		dimmer.orderFront(nil)
		self.dimmer = dimmer
		let rect = host.frame
		window.setFrameOrigin(NSPoint(
			x: rect.midX - window.frame.width / 2,
			y: rect.midY - window.frame.height / 2
		))
		host.addChildWindow(
			window,
			ordered: .above
		)
		lifetime.monitorLocalEvents(matching: [
			.leftMouseDown,
			.rightMouseDown,
			.keyDown
		])
		{
			[weak self, weak host] event in
			guard let self
			else
			{
				return event
			}
			if event.window === host
			{
				self.window?.makeKeyAndOrderFront(nil)
				return nil
			}
			return event
		}
		window.makeKeyAndOrderFront(nil)
		window.makeFirstResponder(window.initialFirstResponder)
	}

	private func updatePresentationGeometry()
	{
		guard let host = presentationHost, let window
		else
		{
			return
		}
		dimmer?.setFrame(
			host.frame,
			display: true
		)
		window.setFrameOrigin(NSPoint(
			x: host.frame.midX - window.frame.width / 2,
			y: host.frame.midY - window.frame.height / 2
		))
		if let fullscreen
		{
			fullscreen.setFrame(
				host.frame,
				display: true
			)
			let size = max(
				0,
				min(
					LayoutTokens.Connections.fullscreenQRSize,
					host.frame.width - 48,
					host.frame.height - 96
				)
			)
			if let qr = fullscreen.contentView?.subviews.first as? RemotePairingQRView
			{
				qr.constraints.first
				{
					$0.firstAttribute == .width
				}?.constant = size
			}
		}
	}

	func setPending(_ pending: Bool)
	{
		isPending = pending
		refreshButtonReference?.isEnabled = !pending
		expandButtonReference?.isEnabled = !pending
		copyButtonReference?.isEnabled = !pending && !manualCode.stringValue.isEmpty
		qr.isHidden = pending || deviceMode == .computer
		manualCode.isHidden = pending || deviceMode == .phone
		if pending
		{
			loading.startAnimation(nil)
		}
		else
		{
			loading.stopAnimation(nil)
		}
	}

	func render(_ pairing: RemoteControlPairing)
	{
		qr.pairingCode = pairing.pairingCode
		manualCode.attributedStringValue = NSAttributedString(
			string: pairing.manualPairingCode ?? "",
			attributes: [
				.font: NSFont.systemFont(
					ofSize: 36,
					weight: .semibold
				),
				.kern: 6.48,
				.foregroundColor: AppKitColorTokens.settingsPrimaryText,
			]
		)
		copyButtonReference?.isEnabled = !isPending && !manualCode.stringValue.isEmpty
		(fullscreen?.contentView?.subviews.first as? RemotePairingQRView)?.pairingCode = pairing
			.pairingCode
	}

	private func select(_ mode: DeviceMode)
	{
		guard deviceMode != mode, let window
		else
		{
			return
		}
		deviceMode = mode
		let computer = mode == .computer
		phoneButton?.presentation = .pairingTab(selected: !computer)
		computerButton?.presentation = .pairingTab(selected: computer)
		phoneButton?.setAccessibilityValue(computer ? "Off" : "On")
		computerButton?.setAccessibilityValue(computer ? "On" : "Off")
		computerInstructions?.isHidden = !computer
		pairingFrameHeight?.constant = computer ? 200 : 248
		expandButtonReference?.isHidden = computer
		copyButtonReference?.isHidden = !computer
		copyButtonReference?.isEnabled = !isPending && !manualCode.stringValue.isEmpty
		qr.isHidden = isPending || computer
		manualCode.isHidden = isPending || !computer
		window.setContentSize(NSSize(
			width: LayoutTokens.Connections.modalWidth,
			height: computer ? LayoutTokens.Connections.computerModalHeight
				: LayoutTokens.Connections.modalHeight
		))
		if let content = window.contentView,
			let mask = content.layer?.mask as? CAShapeLayer
		{
			mask.path = AppKitShapePath.roundedCGPath(
				content.bounds,
				radius: ShapeTokens.Connections.modalRadius,
				curve: ShapeTokens.Connections.curve
			)
		}
		updatePresentationGeometry()
	}

	@objc private func showPhone()
	{
		select(.phone)
	}

	@objc private func showComputer()
	{
		select(.computer)
	}

	@objc private func copyCode()
	{
		guard !manualCode.stringValue.isEmpty
		else
		{
			return
		}
		copyPasteboard.clearContents()
		copyPasteboard.setString(
			manualCode.stringValue,
			forType: .string
		)
	}

	@objc private func closePairing()
	{
		onClose?()
	}
	@objc private func refreshQR()
	{
		onRefresh?()
	}
	@objc private func expandQR()
	{
		guard fullscreen == nil, let host = presentationHost ?? window
		else
		{
			return
		}
		let panel = RemotePairingPanel(
			contentRect: host.frame,
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		panel.backgroundColor = NSColor.black.withAlphaComponent(0.92)
		panel.isReleasedWhenClosed = false
		panel.isOpaque = false
		let view = RemotePairingQRView()
		view.pairingCode = qr.pairingCode
		view.showsLogo = false
		view.translatesAutoresizingMaskIntoConstraints = false
		panel.contentView?.addSubview(view)
		guard let content = panel.contentView
		else
		{
			return
		}
		let size = min(
			LayoutTokens.Connections.fullscreenQRSize,
			host.frame.width - 48,
			host.frame.height - 96
		)
		NSLayoutConstraint.activate([
			view.centerXAnchor.constraint(equalTo: content.centerXAnchor),
			view.centerYAnchor.constraint(equalTo: content.centerYAnchor),
			view.widthAnchor.constraint(equalToConstant: size),
			view.heightAnchor.constraint(equalTo: view.widthAnchor),
		])
		let close = icon(
			.closeBold,
			label: "Close fullscreen QR code",
			action: #selector(closeFullscreen)
		)
		content.addSubview(close)
		NSLayoutConstraint.activate([
			close.topAnchor.constraint(
				equalTo: content.topAnchor,
				constant: 16
			),
			close.trailingAnchor.constraint(
				equalTo: content.trailingAnchor,
				constant: -16
			),
		])
		panel.onCancel =
		{
			[weak self] in self?.closeFullscreen()
		}
		fullscreen = panel
		host.addChildWindow(
			panel,
			ordered: .above
		)
		panel.makeKeyAndOrderFront(nil)
	}

	@objc private func closeFullscreen()
	{
		guard let fullscreen
		else
		{
			return
		}
		fullscreen.parent?.removeChildWindow(fullscreen)
		fullscreen.close()
		self.fullscreen = nil
		window?.makeKey()
	}

	override func close()
	{
		closeFullscreen()
		lifetime.invalidate()
		if let dimmer
		{
			dimmer.parent?.removeChildWindow(dimmer)
			dimmer.close()
		}
		dimmer = nil
		if let window
		{
			window.parent?.removeChildWindow(window)
		}
		presentationHost?.makeKey()
		if let view = previousResponder as? NSView, view.window === presentationHost
		{
			presentationHost?.makeFirstResponder(view)
		}
		super.close()
	}

	static func resourceImage(_ name: String) -> NSImage?
	{
		let base = Bundle.main.resourceURL?.appendingPathComponent("CodexGUI_CodexGUI.bundle")
		let bundle = base.flatMap(Bundle.init(url:)) ?? Bundle.module
		return bundle.url(
			forResource: name,
			withExtension: "png",
			subdirectory: "RemoteAccess"
		)
		.flatMap(NSImage.init(contentsOf:))
	}
}

@MainActor
final class RemotePairingPanel: NSPanel
{
	var onCancel: (() -> Void)?
	override var canBecomeKey: Bool
	{
		true
	}
	override func cancelOperation(_ sender: Any?)
	{
		onCancel?()
	}
}

@MainActor
final class RemotePairingSegmentTrack: NSView
{
	override func draw(_ dirtyRect: NSRect)
	{
		AppKitColorTokens.pairingSegmentTrack.setFill()
		AppKitShapePath.roundedRect(
			bounds,
			radius: 13,
			curve: ShapeTokens.Connections.curve
		).fill()
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}
}

@MainActor
final class RemotePairingQRView: NSView
{
	var pairingCode = ""
	{
		didSet
		{
			needsDisplay = true
		}
	}
	var showsLogo = true

	static func pairingURL(code: String) -> URL?
	{
		var url = URLComponents(string: "https://chatgpt.com/codex/pair")
		url?.queryItems = [URLQueryItem(
			name: "pairing_code",
			value: code
		)]
		return url?.url
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		guard let url = Self.pairingURL(code: pairingCode),
				let filter = CIFilter(name: "CIQRCodeGenerator")
		else
		{
			return
		}
		filter.setValue(
			Data(url.absoluteString.utf8),
			forKey: "inputMessage"
		)
		filter.setValue(
			"H",
			forKey: "inputCorrectionLevel"
		)
		guard let output = filter.outputImage,
				let image = CIContext().createCGImage(
				output,
				from: output.extent
				),
				let data = image.dataProvider?.data,
				let bytes = CFDataGetBytePtr(data)
		else
		{
			return
		}
		let background = showsLogo ? AppKitColorTokens.pairingQR
			: AppKitColorTokens.fullscreenQR
		let ink = AppKitColorTokens.pairingQRInk
		background.setFill()
		NSBezierPath(
			roundedRect: bounds,
			xRadius: showsLogo ? ShapeTokens.Connections.pairingFrameRadius
				: ShapeTokens.Connections.fullscreenRadius,
			yRadius: showsLogo ? ShapeTokens.Connections.pairingFrameRadius
				: ShapeTokens.Connections.fullscreenRadius
		).fill()
		// Core Image includes a one-module quiet border; data coordinates start inside it.
		let count = image.width - 2
		let cell = bounds.width / CGFloat(count + 8)
		ink.setFill()
		func moduleRect(
			_ x: Int,
			_ y: Int,
			_ size: Int = 1
		) -> NSRect
		{
			NSRect(
				x: CGFloat(x + 4) * cell,
				y: CGFloat(count - y + 4 - size) * cell,
				width: CGFloat(size) * cell,
				height: CGFloat(size) * cell
			)
		}
		for y in 0 ..< count
		{
			for x in 0 ..< count
			{
				let finder = (x < 7 && y < 7) || (x >= count - 7 && y < 7)
					|| (x < 7 && y >= count - 7)
				if !finder &&
					bytes[(y + 1) * image.bytesPerRow + (x + 1) * (image.bitsPerPixel / 8)] < 128
				{
					NSBezierPath(ovalIn: moduleRect(
						x,
						y
					).insetBy(
						dx: cell * 0.06,
						dy: cell * 0.06
					))
					.fill()
				}
			}
		}
		for (x, y) in [(0, 0), (count - 7, 0), (0, count - 7)]
		{
			ink.setFill()
			NSBezierPath(
				roundedRect: moduleRect(
					x,
					y,
					7
				),
				xRadius: cell * 1.5,
				yRadius: cell * 1.5
			)
			.fill()
			background.setFill()
			NSBezierPath(
				roundedRect: moduleRect(
					x + 1,
					y + 1,
					5
				),
				xRadius: cell,
				yRadius: cell
			)
			.fill()
			ink.setFill()
			NSBezierPath(
				roundedRect: moduleRect(
					x + 2,
					y + 2,
					3
				),
				xRadius: cell * 0.75,
				yRadius: cell * 0.75
			).fill()
		}

		if showsLogo, let logo = RemotePairingPanelController.resourceImage("Logo")
		{
			let size = bounds.width * 0.18
			let rect = NSRect(
				x: bounds.midX - size / 2,
				y: bounds.midY - size / 2,
				width: size,
				height: size
			)
			background.setFill()
			rect.insetBy(
				dx: -cell,
				dy: -cell
			).fill()
			logo.draw(in: rect)
		}
	}
}

@MainActor
private final class RemotePairingIconButton: DesktopStyledButton
{
	init(
		icon: DesktopIcon,
		label: String,
		target: AnyObject?,
		action: Selector?
	)
	{
		super.init(
			title: "",
			presentation: .nativeBorderless
		)
		self.target = target
		self.action = action
		image = DesktopIcons.image(icon)
		imagePosition = .imageOnly
		toolTip = label
		setAccessibilityLabel(label)
		translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			widthAnchor.constraint(equalToConstant: 26),
			heightAnchor.constraint(equalToConstant: 26),
		])
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
