import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct SettingsWindowTests
{
	@Test(.appKitIsolation)
	func connectionsRouteOwnsPollingUntilLeavingOrClosingSettings() throws
	{
		_ = NSApplication.shared
		let controller = SettingsViewController()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 1100,
				height: 760
			),
			styleMask: [.titled, .closable, .resizable],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		let container = try #require(window.contentView)
		AppKitLayout.pin(
			controller.view,
			to: container,
			inset: 0
		)
		let remoteContent = try #require(controller.remoteAccess.window?.contentView)
		defer
		{
			controller.endPresentation()
			window.close()
		}
		var commands: [RemoteAccessCommand] = []
		var reconnects = 0
		controller.onReconnect =
		{
			reconnects += 1
		}
		controller.remoteAccess.onCommand =
		{
			commands.append($0)
		}

		window.makeKeyAndOrderFront(nil)
		var remoteModel = RemoteAccessModel()
		remoteModel.status = RemoteControlStatus(
			status: .connected,
			serverName: "Fixture Mac",
			installationId: "fixture",
			environmentId: "fixture"
		)
		controller.remoteAccess.render(
			remoteModel,
			connected: true
		)
		controller.presentConnections()
		let content = try #require(window.contentView)
		let general = try #require(descendants(content).compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.title == "General"
		})
		let connections = try #require(descendants(content).compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.title == "Connections"
		})
		#expect(commands == [.refresh])
		#expect(remoteContent.window === window)
		#expect(descendants(content).contains
		{
			$0 === remoteContent
		})
		#expect(controller.remoteAccess.window?.isVisible == false)
		assertReachable(
			general,
			in: content
		)
		assertReachable(
			connections,
			in: content
		)
		#expect(remoteContent.frame.width > 500)
		#expect(remoteContent.frame.height > 500)
		for size in [
			NSSize(
				width: 1400,
				height: 760
			),
			NSSize(
				width: 900,
				height: 600
			),
			NSSize(
				width: 1100,
				height: 760
			),
		]
		{
			window.setContentSize(size)
			window.layoutIfNeeded()
			content.layoutSubtreeIfNeeded()
			#expect(abs(content.bounds.width - size.width) < 1)
			#expect(abs(content.bounds.height - size.height) < 1)
			#expect(abs(controller.view.bounds.width - size.width) < 1)
			let pageFrame = remoteContent.convert(
				remoteContent.bounds,
				to: controller.view
			)
			#expect(abs(pageFrame.maxX - controller.view.bounds.maxX) < 1)
			#expect(abs(pageFrame.height - controller.view.bounds.height) < 1)
			assertReachable(
				connections,
				in: content
			)
		}

		if let path = ProcessInfo.processInfo.environment["CODEX_GUI_CONNECTIONS_PREVIEW"]
		{
			window.appearance = NSAppearance(named: .darkAqua)
			content.layoutSubtreeIfNeeded()
			try AppTestPNGWriter.write(
				content,
				to: URL(fileURLWithPath: path)
			)
			window.appearance = NSAppearance(named: .aqua)
			content.layoutSubtreeIfNeeded()
			try AppTestPNGWriter.write(
				content,
				to: URL(fileURLWithPath: path + ".light.png")
			)
			window.appearance = NSAppearance(named: .darkAqua)
		}
		#expect(general.dispatchConfiguredAction())
		assertReachable(
			connections,
			in: content
		)
		#expect(commands == [.refresh, .clearPairing])
		let reconnect = try #require(descendants(content).compactMap
		{
			$0 as? NSButton
		}
		.first
		{
			$0.title == "Reconnect"
		})
		content.layoutSubtreeIfNeeded()
		reconnect.scrollToVisible(reconnect.bounds)
		assertReachable(
			reconnect,
			in: content
		)
		#expect(reconnect.dispatchConfiguredAction())
		#expect(reconnects == 1)
		#expect(descendants(content).compactMap
		{
			$0 as? NSButton
		}.contains
		{
			$0.title == "Reconnect"
		})
		#expect(connections.dispatchConfiguredAction())
		#expect(commands == [.refresh, .clearPairing, .refresh])

		controller.endPresentation()
		#expect(commands == [.refresh, .clearPairing, .refresh, .clearPairing])
		controller.present()
		#expect(commands == [.refresh, .clearPairing, .refresh, .clearPairing])
		let editor = try #require(descendants(content).compactMap
		{
			$0 as? SettingsEditorPicker
		}.first)
		content.layoutSubtreeIfNeeded()
		editor.scrollToVisible(editor.bounds)
		var editorRequests = 0
		editor.onChooseEditor =
		{
			editorRequests += 1
		}
		#expect(editor.dispatchConfiguredAction())
		let editorMenu = try #require(window.childWindows?.first?.contentView)
		let chooseEditor = try #require(descendants(editorMenu).compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.title == "Choose Editor…"
		})
		#expect(chooseEditor.dispatchConfiguredAction())
		#expect(editorRequests == 1)
		assertReachable(
			connections,
			in: content
		)
	}

	@Test(.appKitIsolation)
	func accountSettingsUsesMainWindowAndBackRestoresWorkspace() throws
	{
		_ = NSApplication.shared
		let suite = "SettingsNavigation.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suite))
		let fixture = WorkspaceTestFixture(storage: LocalStorage(defaults: defaults))
		let main = MainWindowController(
			store: fixture.store,
			onOpenProject:
			{
			},
			onInsertPath:
			{
			}
		)
		let window = try #require(main.window)
		window.prepareForTesting()
		window.appearance = NSAppearance(named: .darkAqua)
		defer
		{
			main.close()
			fixture.shutdown()
			defaults.removePersistentDomain(forName: suite)
		}
		main.showWindow(nil)
		window.makeKeyAndOrderFront(nil)
		let workspace = main.paneController.split.view
		let originalToolbar = window.toolbar
		let toolbarWasVisible = window.toolbar?.isVisible
		main.showStatus()
		let menu = try #require(main.statusPopover)
		let settingsAction = main.statusView.menuButtons[1]
		let menuContent = try #require(main.statusView.window?.contentView)
		let settingsPoint = settingsAction.convert(
			NSPoint(
				x: settingsAction.bounds.midX,
				y: settingsAction.bounds.midY
			),
			to: menuContent
		)
		#expect(menuContent.hitTest(settingsPoint) === settingsAction)
		#expect(settingsAction.dispatchConfiguredAction())
		#expect(!menu.isShown)
		#expect(main.settings.view.window === window)
		#expect(workspace.isHidden)
		#expect(workspace.isAccessibilityHidden())
		let search = try #require(descendants(main.settings.view)
			.compactMap
			{
				$0 as? NSSearchField
			}.first)
		#expect(window.firstResponder === search.currentEditor())
		#expect(search.focusRingType == .none)
		let connections = try #require(descendants(main.settings.view)
			.compactMap
			{
				$0 as? NSButton
			}
			.first
			{
				$0.title == "Connections"
			})
		assertReachable(
			connections,
			in: main.settings.view
		)
		let labels = descendants(main.settings.view).compactMap
		{
			$0 as? NSTextField
		}
		let account = try #require(labels.first
		{
			$0.stringValue == "Account"
		})
		let backend = try #require(labels.first
		{
			$0.stringValue == "Backend"
		})
		let accountRect = account.convert(
			account.bounds,
			to: main.settings.view
		)
		let backendRect = backend.convert(
			backend.bounds,
			to: main.settings.view
		)
		#expect(abs(accountRect.midY - backendRect.midY) < 160)
		let bitmap = try #require(main.settings.view.bitmapImageRepForCachingDisplay(
			in: main.settings.view.bounds
		))
		main.settings.view.cacheDisplay(
			in: main.settings.view.bounds,
			to: bitmap
		)
		let title = try #require(labels.first
		{
			$0.stringValue == "Settings"
		})
		for control in [title, connections]
		{
			let rect = control.convert(
				control.bounds,
				to: main.settings.view
			)
			let scale = CGFloat(bitmap.pixelsWide) / main.settings.view.bounds.width
			let pixels = NSRect(
				x: rect.minX * scale,
				y: (main.settings.view.bounds.height - rect.maxY) * scale,
				width: rect.width * scale,
				height: rect.height * scale
			).integral
			var brightPixels = 0
			for y in Int(pixels.minY) ..< Int(pixels.maxY)
			{
				for x in Int(pixels.minX) ..< Int(pixels.maxX)
				{
					if let color = bitmap.colorAt(
						x: x,
						y: y
					)?.usingColorSpace(.deviceRGB),
						min(
							color.redComponent,
							color.greenComponent,
							color.blueComponent
						) > 0.5
					{
						brightPixels += 1
					}
				}
			}
			#expect(
				brightPixels > 10,
				"Sidebar control must be visible in the composed Settings view"
			)
		}
		if let path = ProcessInfo.processInfo.environment["CODEX_GUI_SETTINGS_PREVIEW"]
		{
			try AppTestPNGWriter.write(
				main.settings.view,
				to: URL(fileURLWithPath: path)
			)
		}
		search.stringValue = "connections"
		main.settings.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
		#expect(!connections.isHidden)
		#expect(descendants(main.settings.view).compactMap
		{
			$0 as? NSButton
		}
		.first
		{
			$0.title == "General"
		}?.isHidden == true)
		let toolbarContent = try #require(window.toolbar?.items
			.first
			{
				$0.itemIdentifier == MainWindowController.ToolbarItem.settingsNavigation
			}?
			.view)
		let back = try #require(descendants(toolbarContent).compactMap
		{
			$0 as? NSButton
		}
		.first
		{
			$0.accessibilityLabel() == "Back to chat"
		})
		window.layoutIfNeeded()
		let frameView = try #require(window.contentView?.superview)
		assertReachable(
			back,
			in: frameView
		)
		if let path = ProcessInfo.processInfo.environment["CODEX_GUI_WINDOW_PREVIEW"]
		{
			search.stringValue = ""
			main.settings
				.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
			main.settings.presentConnections()
			var model = RemoteAccessModel()
			model.status = RemoteControlStatus(
				status: .connected,
				serverName: "Fixture Mac",
				installationId: "fixture",
				environmentId: "fixture"
			)
			main.settings.remoteAccess.render(
				model,
				connected: true
			)
			window.layoutIfNeeded()
			frameView.layoutSubtreeIfNeeded()
			try AppTestPNGWriter.write(
				frameView,
				to: URL(fileURLWithPath: path)
			)
		}
		#expect(back.dispatchConfiguredAction())
		#expect(main.settings.view.window == nil)
		#expect(!workspace.isHidden)
		#expect(!workspace.isAccessibilityHidden())
		#expect(window.toolbar === originalToolbar)
		#expect(window.toolbar?.isVisible == toolbarWasVisible)
		main.showSettings()
		#expect(search.stringValue.isEmpty)
		#expect(!connections.isHidden)
		#expect(main.settings.view.window === window)
	}

	private func assertReachable(
		_ button: NSButton,
		in content: NSView
	)
	{
		content.layoutSubtreeIfNeeded()
		let point = button.convert(
			NSPoint(
				x: button.bounds.midX,
				y: button.bounds.midY
			),
			to: content
		)
		#expect(button.bounds.width > 0)
		#expect(button.bounds.height > 0)
		#expect(content.bounds.contains(point))
		#expect(content.hitTest(point) === button)
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		view.subviews.flatMap
		{
			[$0] + descendants($0)
		}
	}
}
