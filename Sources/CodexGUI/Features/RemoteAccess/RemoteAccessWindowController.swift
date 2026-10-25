import AppKit

@MainActor
final class RemoteAccessWindowController: NSWindowController, NSWindowDelegate
{
	var onCommand: ((RemoteAccessCommand) -> Void)?
	var onShowDiagnostics: (() -> Void)?
	private let statusLabel = NSTextField(
		wrappingLabelWithString: "Connect to Codex to check availability."
	)
	private let errorLabel = NSTextField(wrappingLabelWithString: "")
	private let codeLabel = NSTextField(labelWithString: "")
	private let expiryLabel = NSTextField(labelWithString: "")
	private let devices = AppKitLayout.verticalStack(
		[],
		spacing: 8
	)
	private let toggle = NSButton(
		title: "Enable Remote Access",
		target: nil,
		action: nil
	)
	private let pair = NSButton(
		title: "Pair iPhone…",
		target: nil,
		action: nil
	)
	private let refresh = NSButton(
		title: "Refresh",
		target: nil,
		action: nil
	)
	private var current = RemoteAccessModel()
	private var currentConnected: Bool?
	private var deviceRows: [(RemoteControlClient, RemoteAccessDeviceButton)] = []
	private var devicesEnvironmentID: String?
	private var timer: Timer?
	private var ticks = 0
	private var isPolling = false

	init()
	{
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 480,
				height: 470
			),
			styleMask: [.titled, .closable, .resizable],
			backing: .buffered,
			defer: false
		)
		window.title = "Remote Access"
		window.minSize = NSSize(
			width: 460,
			height: 400
		)
		window.center()
		super.init(window: window)
		window.delegate = self
		configureContent()
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	private func configureContent()
	{
		statusLabel.setAccessibilityLabel("Remote access status")
		errorLabel.textColor = .systemRed
		errorLabel.setAccessibilityLabel("Remote access error")
		codeLabel.isSelectable = true
		codeLabel.font = .monospacedSystemFont(
			ofSize: 22,
			weight: .medium
		)
		codeLabel.setAccessibilityLabel("Manual pairing code")
		expiryLabel.textColor = .secondaryLabelColor
		let description = NSTextField(wrappingLabelWithString:
			"Use ChatGPT on your iPhone to connect to this Mac. Sign in to the same account "
				+ "and workspace, then add this computer using the pairing code. "
				+ "Keep Codex GUI open and your Mac awake and online."
		)
		description.textColor = .secondaryLabelColor
		toggle.target = self
		toggle.action = #selector(toggleAccess)
		pair.target = self
		pair.action = #selector(startPairing)
		refresh.target = self
		refresh.action = #selector(refreshStatus)
		let details = NSButton(
			title: "Backend Details…",
			target: self,
			action: #selector(showDiagnostics)
		)
		let stack = AppKitLayout.verticalStack(
			[
				description,
				statusLabel,
				errorLabel,
				AppKitLayout.horizontalStack([toggle, pair]),
				AppKitLayout.horizontalStack([refresh, details]),
				codeLabel,
				expiryLabel,
				AppKitLayout.title("Paired Devices"),
				devices,
			],
			spacing: 12
		)
		let scroll = NSScrollView()
		scroll.hasVerticalScroller = true
		scroll.drawsBackground = false
		let document = RemoteAccessDocumentView()
		document.translatesAutoresizingMaskIntoConstraints = false
		scroll.documentView = document
		window?.contentView = scroll
		stack.translatesAutoresizingMaskIntoConstraints = false
		document.addSubview(stack)
		NSLayoutConstraint.activate([
			document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
			stack.leadingAnchor.constraint(
				equalTo: document.leadingAnchor,
				constant: 20
			),
			stack.trailingAnchor.constraint(
				equalTo: document.trailingAnchor,
				constant: -20
			),
			stack.topAnchor.constraint(
				equalTo: document.topAnchor,
				constant: 20
			),
			stack.bottomAnchor.constraint(
				equalTo: document.bottomAnchor,
				constant: -20
			),
		])
		for label in [description, statusLabel, errorLabel]
		{
			label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		devices.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
	}

	func render(
		_ model: RemoteAccessModel,
		connected: Bool
	)
	{
		guard currentConnected != connected || current != model
		else
		{
			return
		}
		current = model
		currentConnected = connected
		let busy = model.pending != nil
		let enabled = model.status?.status != nil && model.status?.status != .disabled
		toggle.title = enabled ? "Disable Remote Access" : "Enable Remote Access"
		let canStopPendingRead = model.pending?.command == .refresh || model.pending?
			.command == .pair
		toggle.isEnabled = connected && (!busy || enabled && canStopPendingRead)
		pair.isEnabled = connected && !busy && model.canPair
		refresh.isEnabled = connected && !busy
		let status: String
		switch model.status?.status
		{
		case .disabled: status = "Remote access is disabled."
		case .connecting: status = "Connecting to the remote access service…"
		case .connected: status = "Available as \(model.status?.serverName ?? "this Mac")."
		case .errored:
			if model.connectionFailure == .hostAlreadyOnline
			{
				status = "Another Codex app is already using this Mac’s remote connection. "
					+ "Disable remote access in that app, then enable it here."
			}
			else
			{
				status = "The remote access connection failed. "
					+ "Open Backend Details for the connection error."
			}
		case nil: status = "Check availability to set up remote access."
		}
		statusLabel.stringValue = connected ? status : "Connect to Codex to check availability."
		let detail: String?
		if case .reported(let message) = model.connectionFailure
		{
			detail = message
		}
		else
		{
			detail = nil
		}
		errorLabel.stringValue = model.error ?? detail ?? ""
		errorLabel.isHidden = errorLabel.stringValue.isEmpty
		codeLabel.stringValue = model.pairing?.manualPairingCode ?? ""
		codeLabel.isHidden = model.pairing == nil
		expiryLabel.isHidden = model.pairing == nil
		if let pairing = model.pairing
		{
			expiryLabel.stringValue = "Expires " + Date(
				timeIntervalSince1970: Double(pairing.expiresAt)
			).formatted(
				date: .omitted,
				time: .shortened
			)
		}
		renderDevices(
			model,
			enabled: connected && !busy
		)
	}

	private func renderDevices(
		_ model: RemoteAccessModel,
		enabled: Bool
	)
	{
		if devicesEnvironmentID == model.status?.environmentId,
			deviceRows.map(
			{
				$0.0
			}
			) == model.clients
		{
			for (_, button) in deviceRows
			{
				button.isEnabled = enabled
			}
			if !devices.arrangedSubviews.isEmpty
			{
				return
			}
		}
		devicesEnvironmentID = model.status?.environmentId
		deviceRows = []
		for view in devices.arrangedSubviews
		{
			devices.removeArrangedSubview(view)
			view.removeFromSuperview()
		}
		guard let environmentID = model.status?.environmentId, !model.clients.isEmpty
		else
		{
			devices.addArrangedSubview(NSTextField(labelWithString: "No paired devices listed."))
			return
		}
		for client in model.clients
		{
			let name = client.displayName ?? client.deviceModel ?? "Paired device"
			let label = NSTextField(wrappingLabelWithString: name)
			let button = RemoteAccessDeviceButton()
			label.setContentCompressionResistancePriority(
				.defaultLow,
				for: .horizontal
			)
			button.setContentCompressionResistancePriority(
				.required,
				for: .horizontal
			)
			deviceRows.append((client, button))
			button.isEnabled = enabled
			button.setAccessibilityLabel("Remove \(name)")
			let command = onCommand
			button.removeDevice =
			{
				command?(.revoke(
					environmentID: environmentID,
					clientID: client.clientId
				))
			}
			let row = AppKitLayout.horizontalStack([label, button])
			devices.addArrangedSubview(row)
			row.widthAnchor.constraint(equalTo: devices.widthAnchor).isActive = true
		}
	}

	func present()
	{
		showWindow(nil)
		window?.makeKeyAndOrderFront(nil)
		onCommand?(.refresh)
		timer?.invalidate()
		ticks = 0
		isPolling = true
		timer = Timer.scheduledTimer(
			withTimeInterval: 1,
			repeats: true
		)
		{
			[weak self] _ in
			Task
			{
				@MainActor [weak self] in
				self?.tick()
			}
		}
	}

	private func tick()
	{
		guard isPolling
		else
		{
			return
		}
		if current.pairing != nil
		{
			onCommand?(.expirePairing)
		}
		ticks += 1
		if ticks % 5 == 0
		{
			onCommand?(.refresh)
		}
	}

	func windowWillClose(_ notification: Notification)
	{
		isPolling = false
		timer?.invalidate()
		timer = nil
		onCommand?(.clearPairing)
	}

	@objc private func showDiagnostics()
	{
		onShowDiagnostics?()
	}

	@objc private func toggleAccess()
	{
		let enabled = current.status?.status != nil && current.status?.status != .disabled
		onCommand?(.setEnabled(!enabled))
	}
	@objc private func startPairing()
	{
		onCommand?(.pair)
	}
	@objc private func refreshStatus()
	{
		onCommand?(.refresh)
	}
}

@MainActor
private final class RemoteAccessDeviceButton: NSButton
{
	var removeDevice: (() -> Void)?
	init()
	{
		super.init(frame: .zero)
		title = "Remove"
		bezelStyle = .rounded
		target = self
		action = #selector(remove)
	}
	required init?(coder: NSCoder)
	{
		nil
	}
	@objc private func remove()
	{
		removeDevice?()
	}
}

@MainActor
private final class RemoteAccessDocumentView: NSView
{
	override var isFlipped: Bool
	{
		true
	}
}
