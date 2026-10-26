import AppKit
import Vision
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct RemoteAccessWindowTests
{
	@Test func deviceRemovalUsesItsCapturedIdentityAndDisconnectedControlsAreDisabled() throws
	{
		let controller = RemoteAccessWindowController()
		defer
		{
			controller.close()
		}
		var commands: [RemoteAccessCommand] = []
		controller.onCommand =
		{
			commands.append($0)
		}
		var model = RemoteAccessModel()
		model.status = RemoteControlStatus(
			status: .connected,
			serverName: "Test Mac",
			installationId: "installation",
			environmentId: "environment"
		)
		model.pairing = RemoteControlPairing(
			pairingCode: "synthetic-pairing-code",
			manualPairingCode: "ABCD-EFGH",
			environmentId: "environment",
			expiresAt: 2_000_000_000
		)
		model.clients = [RemoteControlClient(
			clientId: "phone",
			displayName: "My iPhone with a longer device name and location details",
			deviceType: "phone",
			platform: "ios",
			osVersion: nil,
			deviceModel: nil,
			appVersion: nil,
			lastSeenAt: nil
		)]
		controller.render(
			model,
			connected: true
		)
		let content = try #require(controller.window?.contentView)
		content.layoutSubtreeIfNeeded()
		let scroll = try #require(content as? NSScrollView)
		let document = try #require(scroll.documentView)
		#expect(document.bounds.width >= 400)
		#expect(document.bounds.height > 200)
		if let capture = ProcessInfo.processInfo.environment["CODEX_GUI_REMOTE_PREVIEW"]
		{
			let bitmap = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
			content.cacheDisplay(
				in: content.bounds,
				to: bitmap
			)
			let data = try #require(bitmap.representation(
				using: .png,
				properties: [:]
			))
			try data.write(to: URL(fileURLWithPath: capture))
		}

		let buttons = descendants(content).compactMap
		{
			$0 as? NSButton
		}
		let remove = try #require(buttons.first
		{
			$0.title == "Revoke access"
		})
		let removeFrame = remove.convert(
			remove.bounds,
			to: scroll.contentView
		)
		#expect(removeFrame.minX >= 0 && removeFrame.maxX <= scroll.contentView.bounds.width)
		let add = try #require(buttons.first
		{
			$0.title == "Add"
		})
		let refresh = try #require(buttons.first
		{
			$0.toolTip == "Refresh"
		})
		let addFrame = add.convert(
			add.bounds,
			to: content
		)
		let refreshFrame = refresh.convert(
			refresh.bounds,
			to: content
		)
		#expect(abs(addFrame.midY - refreshFrame.midY) < 1)
		#expect(addFrame.minX > refreshFrame.maxX)
		#expect(abs(removeFrame.maxX - addFrame.maxX + 17) < 1)
		let hint = try #require(descendants(content).compactMap
		{
			$0 as? NSTextField
		}.first
		{
			$0.stringValue == "Add device to control this Mac remotely"
		})
		#expect(hint.isHiddenOrHasHiddenAncestor)
		#expect(descendants(content).compactMap
		{
			$0 as? NSTextField
		}.contains
		{
			$0.stringValue == "Authorized device" && !$0.isHiddenOrHasHiddenAncestor
		})
		#expect(remove.sendAction(
			remove.action,
			to: remove.target
		))
		#expect(commands == [.revoke(
			environmentID: "environment",
			clientID: "phone"
		)])
		controller.render(
			model,
			connected: false
		)
		#expect(buttons.filter
		{
			["Add", "Revoke access"].contains($0.title) || $0.toolTip == "Refresh"
		}.allSatisfy
		{
			!$0.isEnabled
		})
		model.clients = []
		controller.render(
			model,
			connected: true
		)
		content.layoutSubtreeIfNeeded()
		#expect(!hint.isHiddenOrHasHiddenAncestor)
		#expect(add.superview !== refresh.superview)
		controller.beginPresentation()
		controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
		#expect(commands.last == .clearPairing)
	}

	@Test func hostConflictRemainsVisibleAndAllowsPairingAttempt() throws
	{
		let controller = RemoteAccessWindowController()
		var commands: [RemoteAccessCommand] = []
		controller.onCommand =
		{
			commands.append($0)
		}
		defer
		{
			controller.close()
		}
		var model = RemoteAccessModel()
		model.status = RemoteControlStatus(
			status: .errored,
			serverName: "Test Mac",
			installationId: "installation",
			environmentId: "environment"
		)
		model.connectionFailure = .hostAlreadyOnline
		controller.render(
			model,
			connected: true
		)
		let content = try #require(controller.window?.contentView)
		let labels = descendants(content).compactMap
		{
			$0 as? NSTextField
		}
		#expect(labels.contains
		{
			$0.stringValue.contains("Another Codex app")
		})
		#expect(labels.contains
		{
			$0.stringValue.contains("Disable remote access in that app")
		})
		let pair = try #require(descendants(content).compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.title == "Add"
		})
		#expect(pair.isEnabled)
		#expect(pair.dispatchConfiguredAction())
		#expect(commands == [.pair])
	}

	@Test func addAndRefreshRouteCommandsAndLeavingSettingsClearsPairingOnce() throws
	{
		let controller = RemoteAccessWindowController()
		defer
		{
			controller.close()
		}
		var commands: [RemoteAccessCommand] = []
		controller.onCommand =
		{
			commands.append($0)
		}
		var model = RemoteAccessModel()
		model.status = RemoteControlStatus(
			status: .connected,
			serverName: "Mac",
			installationId: "installation",
			environmentId: "environment"
		)
		controller.render(
			model,
			connected: true
		)
		let content = try #require(controller.window?.contentView)
		let buttons = descendants(content).compactMap
		{
			$0 as? NSButton
		}
		let add = try #require(buttons.first
		{
			$0.title == "Add"
		})
		controller.window?.layoutIfNeeded()
		content.layoutSubtreeIfNeeded()
		let switches = descendants(content).compactMap
		{
			$0 as? RemoteConnectionsSwitch
		}
		#expect(switches.count == 2)
		for control in switches
		{
			#expect(control.bounds.size == NSSize(
				width: 32,
				height: 20
			))
			#expect(control.state == .on)
		}
		#expect(add.bounds.height == 24)
		let hint = try #require(descendants(content).compactMap
		{
			$0 as? NSTextField
		}
		.first
		{
			$0.stringValue == "Add device to control this Mac remotely"
		})
		let addFrame = add.convert(
			add.bounds,
			to: content
		)
		let hintFrame = hint.convert(
			hint.bounds,
			to: content
		)
		#expect(abs(addFrame.midX - hintFrame.midX) < 1)
		#expect(!buttons
			.contains
			{
				$0.title == "Backend Details…" && !$0.isHiddenOrHasHiddenAncestor
			})
		#expect(add.isEnabled)
		#expect(add.sendAction(
			add.action,
			to: add.target
		))
		#expect(commands == [.pair])
		let unsupported = buttons.filter
		{
			["Control other devices", "SSH"].contains($0.title)
		}
		#expect(unsupported.count == 2)
		#expect(unsupported.allSatisfy
		{
			!$0.isEnabled
		})
		controller.beginPresentation()
		controller.beginPresentation()
		#expect(commands == [.pair, .refresh])
		controller.endPresentation()
		controller.endPresentation()
		#expect(commands == [.pair, .refresh, .clearPairing])
		let allow = try #require(switches.first
		{
			$0.accessibilityLabel() == "Allow connections"
		})
		controller.window?.appearance = NSAppearance(named: .darkAqua)
		// Native button cells can advance state without calling the view's state setter.
		allow.setNextState()
		#expect(allow.state == .off)
		let bitmap = try #require(allow.bitmapImageRepForCachingDisplay(in: allow.bounds))
		allow.cacheDisplay(
			in: allow.bounds,
			to: bitmap
		)
		let scale = CGFloat(bitmap.pixelsWide) / allow.bounds.width
		let thumb = try #require(bitmap.colorAt(
			x: Int(10 * scale),
			y: Int(10 * scale)
		)?
			.usingColorSpace(.deviceRGB))
		#expect(thumb.redComponent > 0.9 && thumb.greenComponent > 0.9 && thumb
			.blueComponent > 0.9 && thumb.alphaComponent > 0.9)
		#expect(allow.dispatchConfiguredAction())
		#expect(commands.last == .setEnabled(false))
	}

	@Test func pairingLinkPreservesTheServerTokenAsOneQueryValue() throws
	{
		let token = "server+token/with?reserved=& characters"
		let url = try #require(RemotePairingQRView.pairingURL(code: token))
		let components = try #require(URLComponents(
			url: url,
			resolvingAgainstBaseURL: false
		))
		#expect(components.scheme == "https")
		#expect(components.host == "chatgpt.com")
		#expect(components.path == "/codex/pair")
		#expect(components.queryItems == [URLQueryItem(
			name: "pairing_code",
			value: token
		)])
	}

	@Test(.appKitIsolation)
	func pairingModeSwitchKeepsTheServerCodeAndResizesTheDialog() throws
	{
		_ = NSApplication.shared
		let controller = RemoteAccessWindowController()
		let host = try #require(controller.window)
		host.prepareForTesting()
		defer
		{
			controller.close()
		}
		controller.present()
		var model = RemoteAccessModel()
		model.status = RemoteControlStatus(
			status: .connected,
			serverName: "Mac",
			installationId: "installation",
			environmentId: "environment"
		)
		model.pairing = RemoteControlPairing(
			pairingCode: "server-token",
			manualPairingCode: "ABCD-EFGH",
			environmentId: "environment",
			expiresAt: 2_000_000_000
		)
		controller.render(
			model,
			connected: true
		)
		let pairing = try #require(controller.pairingController)
		let panel = try #require(pairing.window)
		let content = try #require(panel.contentView)
		#expect(panel.contentLayoutRect.size == NSSize(
			width: 420,
			height: 642
		))
		let artwork = try #require(descendants(content).first
		{
			$0 is RemotePairingArtworkView
		})
		let segments = try #require(descendants(content).first
		{
			$0 is RemotePairingSegmentTrack
		})
		content.layoutSubtreeIfNeeded()
		#expect(artwork.bounds.height == 214)
		#expect(segments.bounds.height == 36)
		let buttons = descendants(content).compactMap
		{
			$0 as? NSButton
		}
		let computer = try #require(buttons.first
		{
			$0.title == "Computer"
		})
		let phone = try #require(buttons.first
		{
			$0.title == "Phone"
		})
		#expect(computer.isEnabled)
		#expect(computer.bounds.height == 28)
		#expect(computer.dispatchConfiguredAction())
		content.layoutSubtreeIfNeeded()
		#expect(panel.contentLayoutRect.size == NSSize(
			width: 420,
			height: 649
		))
		let code = try #require(descendants(content).compactMap
		{
			$0 as? NSTextField
		}
		.first
		{
			$0.accessibilityLabel() == "Manual pairing code"
		})
		#expect(code.stringValue == "ABCD-EFGH")
		#expect(!code.isHiddenOrHasHiddenAncestor)
		let qr = try #require(descendants(content).first
		{
			$0 is RemotePairingQRView
		})
		#expect(qr.isHidden)
		let copy = try #require(buttons.first
		{
			$0.toolTip == "Copy pairing code"
		})
		#expect(copy.isEnabled && !copy.isHiddenOrHasHiddenAncestor)
		#expect(phone.dispatchConfiguredAction())
		content.layoutSubtreeIfNeeded()
		#expect(panel.contentLayoutRect.size == NSSize(
			width: 420,
			height: 642
		))
		#expect(!qr.isHidden)
		#expect(code.isHidden)
	}

	@Test(.appKitIsolation)
	func computerPairingCopiesOnlyTheCurrentManualCode() throws
	{
		_ = NSApplication.shared
		let pasteboard = NSPasteboard.withUniqueName()
		defer
		{
			pasteboard.releaseGlobally()
		}
		let pairing = RemotePairingPanelController(pasteboard: pasteboard)
		defer
		{
			pairing.close()
		}
		let content = try #require(pairing.window?.contentView)
		let buttons = descendants(content).compactMap
		{
			$0 as? NSButton
		}
		let computer = try #require(buttons.first
		{
			$0.title == "Computer"
		})
		let copy = try #require(buttons.first
		{
			$0.toolTip == "Copy pairing code"
		})
		#expect(computer.dispatchConfiguredAction())
		#expect(!copy.isEnabled)
		pairing.render(RemoteControlPairing(
			pairingCode: "server-token-one",
			manualPairingCode: "ABCD-EFGH",
			environmentId: "environment",
			expiresAt: 2_000_000_000
		))
		#expect(copy.dispatchConfiguredAction())
		#expect(pasteboard.string(forType: .string) == "ABCD-EFGH")
		pairing.render(RemoteControlPairing(
			pairingCode: "server-token-two",
			manualPairingCode: "WXYZ-1234",
			environmentId: "environment",
			expiresAt: 2_000_000_000
		))
		#expect(copy.dispatchConfiguredAction())
		#expect(pasteboard.string(forType: .string) == "WXYZ-1234")
	}

	@Test(.appKitIsolation)
	func connectionSwitchAndPairingQRRepaintForBothAppearances() throws
	{
		_ = NSApplication.shared
		let panel = NSPanel(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 240,
				height: 240
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		defer
		{
			panel.close()
		}
		let content = try #require(panel.contentView)
		let control = RemoteConnectionsSwitch(frame: NSRect(
			x: 16,
			y: 16,
			width: 32,
			height: 20
		))
		control.state = .on
		content.addSubview(control)
		let qr = RemotePairingQRView(frame: NSRect(
			x: 48,
			y: 48,
			width: 180,
			height: 180
		))
		qr.pairingCode = "appearance-test"
		content.addSubview(qr)
		let referenceTrack = RemoteReferenceColorSwatch(frame: NSRect(
			x: 0,
			y: 0,
			width: 16,
			height: 16
		))
		content.addSubview(referenceTrack)
		let referenceBackground = RemoteReferenceColorSwatch(frame: NSRect(
			x: 0,
			y: 48,
			width: 16,
			height: 16
		))
		content.addSubview(referenceBackground)
		for (appearance, blue, background) in [
			(NSAppearance.Name.aqua, NSColor(
				srgbRed: 1 / 255,
				green: 105 / 255,
				blue: 204 / 255,
				alpha: 1
			), NSColor.white),
			(NSAppearance.Name.darkAqua, NSColor(
				srgbRed: 58 / 255,
				green: 131 / 255,
				blue: 247 / 255,
				alpha: 1
			), NSColor(
				white: 24 / 255,
				alpha: 1
			)),
		]
		{
			panel.appearance = NSAppearance(named: appearance)
			referenceTrack.color = blue
			referenceBackground.color = background
			let switchBitmap = try #require(control.bitmapImageRepForCachingDisplay(
				in: control.bounds
			))
			control.cacheDisplay(
				in: control.bounds,
				to: switchBitmap
			)
			let switchScale = CGFloat(switchBitmap.pixelsWide) / control.bounds.width
			let track = try #require(switchBitmap.colorAt(
				x: Int(8 * switchScale),
				y: Int(10 * switchScale)
			)?
				.usingColorSpace(.deviceRGB))
			let trackBitmap = try #require(referenceTrack.bitmapImageRepForCachingDisplay(
				in: referenceTrack.bounds
			))
			referenceTrack.cacheDisplay(
				in: referenceTrack.bounds,
				to: trackBitmap
			)
			let expectedBlue = try #require(trackBitmap.colorAt(
				x: trackBitmap.pixelsWide / 2,
				y: trackBitmap.pixelsHigh / 2
			)?
				.usingColorSpace(.deviceRGB))
			#expect(abs(track.redComponent - expectedBlue.redComponent) < 0.03)
			#expect(abs(track.greenComponent - expectedBlue.greenComponent) < 0.03)
			#expect(abs(track.blueComponent - expectedBlue.blueComponent) < 0.03)
			let qrBitmap = try #require(qr.bitmapImageRepForCachingDisplay(in: qr.bounds))
			qr.cacheDisplay(
				in: qr.bounds,
				to: qrBitmap
			)
			let qrScale = CGFloat(qrBitmap.pixelsWide) / qr.bounds.width
			let quietZone = try #require(qrBitmap.colorAt(
				x: Int(90 * qrScale),
				y: Int(8 * qrScale)
			)?
				.usingColorSpace(.deviceRGB))
			let backgroundBitmap = try #require(
				referenceBackground.bitmapImageRepForCachingDisplay(in: referenceBackground.bounds)
			)
			referenceBackground.cacheDisplay(
				in: referenceBackground.bounds,
				to: backgroundBitmap
			)
			let expectedBackground = try #require(backgroundBitmap.colorAt(
				x: backgroundBitmap.pixelsWide / 2,
				y: backgroundBitmap.pixelsHigh / 2
			)?
				.usingColorSpace(.deviceRGB))
			#expect(abs(quietZone.redComponent - expectedBackground.redComponent) < 0.03)
			#expect(abs(quietZone.greenComponent - expectedBackground.greenComponent) < 0.03)
			#expect(abs(quietZone.blueComponent - expectedBackground.blueComponent) < 0.03)
		}
	}

	@Test(arguments: [180.0, 540.0])
	func pairingQRCodeWithCenterLogoDecodesToTheServerLink(size: Double) throws
	{
		let qr = RemotePairingQRView(frame: NSRect(
			x: 0,
			y: 0,
			width: size,
			height: size
		))
		qr.pairingCode = String(
			repeating: "synthetic-server-token-",
			count: 5
		)
		let bitmap = try #require(qr.bitmapImageRepForCachingDisplay(in: qr.bounds))
		qr.cacheDisplay(
			in: qr.bounds,
			to: bitmap
		)
		if let path = ProcessInfo.processInfo.environment["CODEX_GUI_QR_PREVIEW"]
		{
			let png = try #require(bitmap.representation(
				using: .png,
				properties: [:]
			))
			try png.write(to: URL(fileURLWithPath: path + "-\(Int(size)).png"))
		}
		let image = try #require(bitmap.cgImage)
		let request = VNDetectBarcodesRequest()
		request.symbologies = [.qr]
		try VNImageRequestHandler(cgImage: image).perform([request])
		#expect(request.results?.first?.payloadStringValue
			== RemotePairingQRView.pairingURL(code: qr.pairingCode)?.absoluteString)
	}

	@Test(.appKitIsolation)
	func pairingRefreshRetainsDialogAndEscapeRetiresOnlyTheCurrentPresentation() throws
	{
		_ = NSApplication.shared
		let controller = RemoteAccessWindowController()
		let host = try #require(controller.window)
		host.prepareForTesting()
		defer
		{
			controller.close()
		}
		var commands: [RemoteAccessCommand] = []
		controller.onCommand =
		{
			commands.append($0)
		}
		controller.present()
		var model = RemoteAccessModel()
		model.status = RemoteControlStatus(
			status: .connected,
			serverName: "Mac",
			installationId: "installation",
			environmentId: "environment"
		)
		model.pairing = RemoteControlPairing(
			pairingCode: "token",
			manualPairingCode: "12345678",
			environmentId: "environment",
			expiresAt: 2_000_000_000
		)
		controller.render(
			model,
			connected: true
		)
		let pairing = try #require(controller.pairingController)
		let panel = try #require(pairing.window)
		#expect(panel.parent === host)
		host.setFrame(
			NSRect(
				x: 100,
				y: 100,
				width: 1000,
				height: 850
			),
			display: true
		)
		#expect(abs(panel.frame.midX - host.frame.midX) < 1)
		#expect(abs(panel.frame.midY - host.frame.midY) < 1)
		let content = try #require(panel.contentView)
		let expand = try #require(descendants(content).compactMap
		{
			$0 as? NSButton
		}
		.first
		{
			$0.toolTip == "Show QR code fullscreen"
		})
		#expect(expand.sendAction(
			expand.action,
			to: expand.target
		))
		let fullscreen = try #require(pairing.fullscreen)
		fullscreen.cancelOperation(nil)
		#expect(pairing.fullscreen == nil)
		#expect(controller.pairingController === pairing)
		let refresh = try #require(descendants(content).compactMap
		{
			$0 as? NSButton
		}
		.first
		{
			$0.toolTip == "Refresh pairing code"
		})
		#expect(refresh.sendAction(
			refresh.action,
			to: refresh.target
		))
		#expect(commands.last == .pair)
		model.pairing = nil
		model.pending = RemoteAccessOperation(
			context: OperationContext(
				workspace: WorkspaceIdentity(
					sessionID: UUID(),
					canonicalCheckoutPath: nil
				),
				generation: 1,
				requestID: UUID()
			),
			command: .pair,
			statusRevision: 0
		)
		controller.render(
			model,
			connected: true
		)
		#expect(controller.pairingController === pairing)
		#expect(!refresh.isEnabled)
		#expect(!expand.isEnabled)
		panel.cancelOperation(nil)
		#expect(commands.last == .clearPairing)
		controller.endPresentation()
		#expect(controller.pairingController == nil)
		#expect(panel.parent == nil)
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap(descendants)
	}
}

@MainActor
private final class RemoteReferenceColorSwatch: NSView
{
	var color: NSColor = .clear
	{
		didSet
		{
			needsDisplay = true
		}
	}

	override func draw(_ dirtyRect: NSRect)
	{
		color.setFill()
		NSBezierPath(rect: bounds).fill()
	}
}
