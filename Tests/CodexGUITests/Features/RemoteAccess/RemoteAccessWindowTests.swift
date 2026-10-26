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
		let description = try #require(descendants(content).compactMap
		{
			$0 as? NSTextField
		}.first
		{
			$0.stringValue.hasPrefix("Use ChatGPT")
		})
		let descriptionFrame = description.convert(
			description.bounds,
			to: scroll.contentView
		)
		#expect(descriptionFrame.minY >= 0 && descriptionFrame.minY < 30)
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
			$0.title == "Remove"
		})
		let removeFrame = remove.convert(
			remove.bounds,
			to: scroll.contentView
		)
		#expect(removeFrame.minX >= 0 && removeFrame.maxX <= scroll.contentView.bounds.width)
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
			$0.title != "Backend Details…"
		}.allSatisfy
		{
			!$0.isEnabled
		})
		controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
		#expect(commands.last == .clearPairing)
	}

	@Test func hostConflictExplainsWhyPairingIsUnavailable() throws
	{
		let controller = RemoteAccessWindowController()
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
			$0.title == "Pair iPhone…"
		})
		#expect(!pair.isEnabled)
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap(descendants)
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

}
