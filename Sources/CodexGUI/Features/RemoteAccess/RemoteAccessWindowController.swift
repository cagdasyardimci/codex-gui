import AppKit

@MainActor
final class RemoteAccessWindowController: NSWindowController, NSWindowDelegate
{
	var onCommand: ((RemoteAccessCommand) -> Void)?
	private var emptyState = NSStackView()
	private let emptyRow = NSView()
	private let headerActions = AppKitLayout.horizontalStack(
		[],
		spacing: 8
	)
	private let awakeToggle = RemoteConnectionsSwitch(frame: .zero)
	private let awakeService = RemoteAccessAwakeService()
	private(set) var pairingController: RemotePairingPanelController?
	private let devices = AppKitLayout.verticalStack(
		[],
		spacing: 0
	)
	private let toggle = RemoteConnectionsSwitch(frame: .zero)
	private let pair = RemoteConnectionsButton(
		title: "Add",
		presentation: .primary
	)
	private let refresh = RemoteConnectionsButton(
		title: "",
		presentation: .icon
	)
	private var current = RemoteAccessModel()
	private var currentConnected: Bool?
	private var deviceRows: [(RemoteControlClient, DesktopActionButton, NSTextField)] = []
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
		window.isReleasedWhenClosed = false
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
		window?.title = "Connections"
		window?.setContentSize(NSSize(
			width: 840,
			height: 700
		))
		toggle.setAccessibilityLabel("Allow connections")
		toggle.target = self
		toggle.action = #selector(toggleAccess)
		pair.target = self
		pair.action = #selector(startPairing)
		refresh.image = RemoteConnectionsArtwork.image(named: "Refresh")
		refresh.toolTip = "Refresh"
		refresh.setAccessibilityLabel("Refresh")
		refresh.target = self
		refresh.action = #selector(refreshStatus)
		let heading = RemoteConnectionsLabel(
			"Connections",
			role: TypographyTokens.Connections.title
		)
		headerActions.addArrangedSubview(refresh)
		let section = sectionHeader(
			"Devices that can control this Mac",
			accessory: headerActions
		)
		let artwork = RemoteConnectionsArtwork()
		emptyState = AppKitLayout.verticalStack(
			[artwork, pair],
			spacing: 12
		)
		emptyState.alignment = .centerX
		AppKitLayout.pin(
			emptyState,
			to: emptyRow,
			inset: 24
		)
		let allowLabel = RemoteConnectionsLabel(
			"Allow connections",
			role: TypographyTokens.Connections.rowLabel
		)
		let allowRow = NSView()
		let allowContents = AppKitLayout.horizontalStack(
			[allowLabel, NSView(), toggle],
			spacing: 24
		)
		allowRow.addSubview(allowContents)
		allowContents.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			allowContents.leadingAnchor.constraint(
				equalTo: allowRow.leadingAnchor,
				constant: 16
			),
			allowContents.trailingAnchor.constraint(
				equalTo: allowRow.trailingAnchor,
				constant: -16
			),
			allowContents.centerYAnchor.constraint(equalTo: allowRow.centerYAnchor),
		])
		allowRow.heightAnchor.constraint(equalToConstant: 44).isActive = true
		let divider = SettingsSurfaceView(color: AppKitColorTokens.connectionsEdge)
		divider.translatesAutoresizingMaskIntoConstraints = false
		allowRow.addSubview(divider)
		NSLayoutConstraint.activate([
			divider.leadingAnchor.constraint(
				equalTo: allowRow.leadingAnchor,
				constant: 16
			),
			divider.trailingAnchor.constraint(
				equalTo: allowRow.trailingAnchor,
				constant: -16
			),
			divider.bottomAnchor.constraint(equalTo: allowRow.bottomAnchor),
			divider.heightAnchor.constraint(equalToConstant: 1),
		])
		let card = RemoteConnectionsCard()
		let contents = AppKitLayout.verticalStack(
			[allowRow, devices, emptyRow],
			spacing: 0
		)
		AppKitLayout.pin(
			contents,
			to: card,
			inset: 1
		)
		for row in [allowRow, devices, emptyRow]
		{
			row.widthAnchor.constraint(equalTo: contents.widthAnchor).isActive = true
		}
		devices.isHidden = true
		let awakeTitle = RemoteConnectionsLabel(
			"Keep this Mac awake",
			role: TypographyTokens.Connections.rowLabel
		)
		let awakeDetail = RemoteConnectionsLabel(
			"Prevent sleep when computer is plugged in and remote access is enabled",
			role: TypographyTokens.Connections.caption
		)
		awakeDetail.textColor = AppKitColorTokens.settingsSecondaryText
		let awakeText = AppKitLayout.verticalStack(
			[awakeTitle, awakeDetail],
			spacing: 2
		)
		awakeToggle.setAccessibilityLabel("Keep this Mac awake")
		awakeToggle.state = .on
		awakeToggle.target = self
		awakeToggle.action = #selector(toggleAwake)
		let sun = RemoteConnectionsArtwork(
			name: "Sun",
			size: NSSize(
				width: 18,
				height: 18
			)
		)
		let awake = AppKitLayout.horizontalStack(
			[sun, awakeText, NSView(), awakeToggle],
			spacing: 12
		)
		awakeText.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		let awakeCard = RemoteConnectionsCard()
		awake.translatesAutoresizingMaskIntoConstraints = false
		awakeCard.addSubview(awake)
		NSLayoutConstraint.activate([
			awake.leadingAnchor.constraint(
				equalTo: awakeCard.leadingAnchor,
				constant: 17
			),
			awake.trailingAnchor.constraint(
				equalTo: awakeCard.trailingAnchor,
				constant: -17
			),
			awake.topAnchor.constraint(
				equalTo: awakeCard.topAnchor,
				constant: 13
			),
			awake.bottomAnchor.constraint(
				equalTo: awakeCard.bottomAnchor,
				constant: -13
			),
		])
		let deviceSection = AppKitLayout.verticalStack(
			[section, card],
			spacing: 0
		)
		let otherHeader = sectionHeader("Other settings")
		let otherSection = AppKitLayout.verticalStack(
			[otherHeader, awakeCard],
			spacing: 0
		)
		let stack = AppKitLayout.verticalStack(
			[heading, deviceSection, otherSection],
			spacing: 40
		)
		stack.setCustomSpacing(
			LayoutTokens.Connections.titleTabGap,
			after: heading
		)
		window?.contentView = SettingsPageLayout.scrollableDocument(
			content: stack,
			columnWidth: .fitsViewport
		)
		for row in [
			deviceSection,
			section,
			card,
			otherSection,
			otherHeader,
			awakeCard
		]
		{
			row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
	}

	private func sectionHeader(
		_ title: String,
		accessory: NSView? = nil
	) -> NSView
	{
		let header = NSView()
		let label = RemoteConnectionsLabel(
			title,
			role: TypographyTokens.Connections.section
		)
		let row = AppKitLayout.horizontalStack(
			[label, NSView()] + (accessory.map
			{
				[$0]
			} ?? []),
			spacing: 16
		)
		header.addSubview(row)
		row.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			header.heightAnchor.constraint(equalToConstant: 46),
			row.leadingAnchor.constraint(equalTo: header.leadingAnchor),
			row.trailingAnchor.constraint(equalTo: header.trailingAnchor),
			row.centerYAnchor.constraint(
				equalTo: header.centerYAnchor,
				constant: 3
			),
		])
		return header
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
		toggle.state = enabled ? .on : .off
		let canStopPendingRead = model.pending?.command == .refresh || model.pending?
			.command == .pair
		toggle.isEnabled = connected && (!busy || enabled && canStopPendingRead)
		pair.isEnabled = connected && !busy
		refresh.isEnabled = connected && !busy
		pair.title = "Add"
		pair.isLoading = model.pending?.command == .pair
		let hasDevices = !model.clients.isEmpty
		emptyRow.isHidden = hasDevices
		let pairContainer = hasDevices ? headerActions : emptyState
		if pair.superview !== pairContainer
		{
			(pair.superview as? NSStackView)?.removeArrangedSubview(pair)
			pair.removeFromSuperview()
			pairContainer.addArrangedSubview(pair)
		}
		devices.isHidden = model.clients.isEmpty
		awakeService.update(enabled: model.status?.status == .connected
			&& connected && awakeToggle.state == .on)
		renderPairing(
			model.pairing,
			pending: model.pending?.command == .pair
		)
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
			for (client, button, subtitle) in deviceRows
			{
				button.isEnabled = enabled
				subtitle.stringValue = Self.deviceDetail(
					client,
					now: Date()
				)
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
			return
		}
		for client in model.clients
		{
			let name = client.displayName ?? client.deviceModel ?? client.platform ?? client
				.clientId
			let label = RemoteConnectionsLabel(
				name,
				role: TypographyTokens.Connections.rowLabel
			)
			let subtitle = RemoteConnectionsLabel(
				Self.deviceDetail(
					client,
					now: Date()
				),
				role: TypographyTokens.Connections.caption
			)
			subtitle.textColor = AppKitColorTokens.settingsSecondaryText
			let text = AppKitLayout.verticalStack(
				[label, subtitle],
				spacing: 2
			)
			let button = DesktopActionButton(
				title: "Revoke access",
				presentation: .secondary
			)
			text.setContentCompressionResistancePriority(
				.defaultLow,
				for: .horizontal
			)
			button.setContentCompressionResistancePriority(
				.required,
				for: .horizontal
			)
			deviceRows.append((client, button, subtitle))
			button.isEnabled = enabled
			button.setAccessibilityLabel("Revoke access for \(name)")
			let command = onCommand
			button.onAction =
			{
				command?(.revoke(
					environmentID: environmentID,
					clientID: client.clientId
				))
			}
			let image: NSView
			if client.deviceType == "phone"
			{
				image = RemoteConnectionsArtwork(
					name: "PairedPhone",
					size: NSSize(
						width: 20,
						height: 20
					)
				)
			}
			else
			{
				let icon = NSImageView(image: DesktopIcons.image(
					.desktop,
					size: 20
				))
				icon.setAccessibilityElement(false)
				image = icon
			}
			let contents = AppKitLayout.horizontalStack(
				[image, text, NSView(), button],
				spacing: 12
			)
			let row = NSView()
			row.addSubview(contents)
			contents.translatesAutoresizingMaskIntoConstraints = false
			NSLayoutConstraint.activate([
				contents.leadingAnchor.constraint(
					equalTo: row.leadingAnchor,
					constant: 16
				),
				contents.trailingAnchor.constraint(
					equalTo: row.trailingAnchor,
					constant: -16
				),
				contents.topAnchor.constraint(
					equalTo: row.topAnchor,
					constant: 12
				),
				contents.bottomAnchor.constraint(
					equalTo: row.bottomAnchor,
					constant: -12
				),
			])
			if !devices.arrangedSubviews.isEmpty
			{
				let divider = SettingsSurfaceView(color: AppKitColorTokens.connectionsEdge)
				row.addSubview(divider)
				divider.translatesAutoresizingMaskIntoConstraints = false
				NSLayoutConstraint.activate([
					divider.leadingAnchor.constraint(
						equalTo: row.leadingAnchor,
						constant: 16
					),
					divider.trailingAnchor.constraint(
						equalTo: row.trailingAnchor,
						constant: -16
					),
					divider.topAnchor.constraint(equalTo: row.topAnchor),
					divider.heightAnchor.constraint(equalToConstant: 1),
				])
			}
			devices.addArrangedSubview(row)
			row.widthAnchor.constraint(equalTo: devices.widthAnchor).isActive = true
		}
	}

	static func deviceDetail(
		_ client: RemoteControlClient,
		now: Date
	) -> String
	{
		guard let lastSeen = client.lastSeenAt
		else
		{
			return "Authorized device"
		}
		let date = Date(timeIntervalSince1970: Double(lastSeen))
		if now.timeIntervalSince(date) < 60
		{
			return "Last connected just now"
		}
		let formatter = RelativeDateTimeFormatter()
		formatter.unitsStyle = .full
		return "Last connected " + formatter.localizedString(
			for: date,
			relativeTo: now
		)
	}

	func present()
	{
		showWindow(nil)
		window?.makeKeyAndOrderFront(nil)
		beginPresentation()
	}

	func beginPresentation()
	{
		guard !isPolling
		else
		{
			return
		}
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
			for (client, _, subtitle) in deviceRows
			{
				subtitle.stringValue = Self.deviceDetail(
					client,
					now: Date()
				)
			}
			onCommand?(.refresh)
		}
	}

	func windowWillClose(_ notification: Notification)
	{
		endPresentation()
	}

	func endPresentation()
	{
		guard isPolling || pairingController != nil
		else
		{
			return
		}
		isPolling = false
		timer?.invalidate()
		timer = nil
		dismissPairing()
		onCommand?(.clearPairing)
	}

	private func renderPairing(
		_ pairing: RemoteControlPairing?,
		pending: Bool
	)
	{
		pairingController?.setPending(pending)
		if pending && pairingController != nil
		{
			return
		}
		guard let pairing
		else
		{
			dismissPairing()
			return
		}
		if pairingController == nil
		{
			guard isPolling, emptyState.window?.isVisible == true
			else
			{
				return
			}
			let panel = RemotePairingPanelController()
			panel.onClose =
			{
				[weak self] in self?.onCommand?(.clearPairing)
			}
			panel.onRefresh =
			{
				[weak self] in self?.onCommand?(.pair)
			}
			pairingController = panel
			if let parent = emptyState.window
			{
				panel.present(over: parent)
			}
		}
		pairingController?.render(pairing)
	}

	private func dismissPairing()
	{
		guard let panel = pairingController
		else
		{
			return
		}
		panel.close()
		pairingController = nil
	}

	@objc private func toggleAwake()
	{
		awakeService.update(enabled: currentConnected == true
			&& current.status?.status == .connected && awakeToggle.state == .on)
	}

	override func close()
	{
		endPresentation()
		awakeService.update(enabled: false)
		super.close()
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
