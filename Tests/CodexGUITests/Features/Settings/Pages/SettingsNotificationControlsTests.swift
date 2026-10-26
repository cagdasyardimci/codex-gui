import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct SettingsNotificationControlsTests
{
	@Test(.appKitIsolation) func authorizationGatesControlsWithoutChangingSavedPreferences() throws
	{
		_ = NSApplication.shared
		let suite = "Notifications.UI.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let preferences = TaskNotificationPreferences(defaults: defaults)
		preferences.completionMode = .whenUnfocused
		preferences.permissionAlerts = true
		preferences.questionAlerts = true
		preferences.sound = .default
		let controls = SettingsNotificationControls(preferences: preferences)
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 860,
				height: 640
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		window.appearance = NSAppearance(named: .aqua)
		defer
		{
			window.close()
		}
		let root = SettingsSurfaceView(color: AppKitColorTokens.canvas)
		window.contentView = root
		controls.translatesAutoresizingMaskIntoConstraints = false
		root.addSubview(controls)
		NSLayoutConstraint.activate([
			controls.widthAnchor.constraint(equalToConstant: 728),
			controls.centerXAnchor.constraint(equalTo: root.centerXAnchor),
			controls.topAnchor.constraint(
				equalTo: root.topAnchor,
				constant: 40
			),
		])
		let completion = try #require(descendants(controls).compactMap
		{
			$0 as? SettingsChoicePicker
		}.first
		{
			$0.accessibilityLabel() == "Turn completion notifications"
		})
		let sound = try #require(descendants(controls).compactMap
		{
			$0 as? SettingsChoicePicker
		}.first
		{
			$0.accessibilityLabel() == "Notification sound"
		})
		let toggles = descendants(controls).compactMap
		{
			$0 as? RemoteConnectionsSwitch
		}
		#expect(toggles.count == 2)
		controls.setAuthorization(.denied)
		window.layoutIfNeeded()
		root.layoutSubtreeIfNeeded()
		let disabledHeight = controls.frame.height
		#expect(!completion.isEnabled && !sound.isEnabled)
		#expect(toggles.allSatisfy
		{
			!$0.isEnabled && $0.state == .on
		})
		#expect(completion.selectedID == "whenUnfocused")
		completion.onSelect?("never")
		#expect(preferences.completionMode == .whenUnfocused)
		try snapshot(
			root,
			suffix: "disabled"
		)

		controls.setAuthorization(.authorized)
		window.layoutIfNeeded()
		root.layoutSubtreeIfNeeded()
		#expect(completion.isEnabled && sound.isEnabled)
		#expect(toggles.allSatisfy
		{
			$0.isEnabled && $0.state == .on
		})
		#expect(disabledHeight - controls.frame.height > 50)
		#expect(disabledHeight - controls.frame.height < 80)
		completion.onSelect?("never")
		#expect(preferences.completionMode == .never)
		#expect(preferences.permissionAlerts && preferences.questionAlerts)
		try snapshot(
			root,
			suffix: "enabled"
		)

		var authorizationRequests = 0
		controls.onRequestAuthorization =
		{
			authorizationRequests += 1
		}
		controls.setAuthorization(.notDetermined)
		let request = try #require(descendants(controls).compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.title == "Allow Notifications"
		})
		#expect(request.dispatchConfiguredAction())
		#expect(authorizationRequests == 1)
		#expect(!completion.isEnabled && !sound.isEnabled)
	}

	@Test func menusExposeTimingAndSoundChoicesInReferenceOrder() async throws
	{
		try await AppKitTestIsolation.perform
		{
			_ = NSApplication.shared
			let suite = "Notifications.Menu.\(UUID().uuidString)"
			let defaults = try #require(UserDefaults(suiteName: suite))
			defer
			{
				defaults.removePersistentDomain(forName: suite)
			}
			let preferences = TaskNotificationPreferences(defaults: defaults)
			let controls = SettingsNotificationControls(preferences: preferences)
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 800,
					height: 600
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			window.prepareForTesting()
			defer
			{
				window.close()
			}
			window.contentView = controls
			controls.setAuthorization(.authorized)
			window.orderFront(nil)
			window.layoutIfNeeded()
			let pickers = descendants(controls).compactMap
			{
				$0 as? SettingsChoicePicker
			}
			let timing = try #require(pickers.first
			{
				$0.accessibilityLabel() == "Turn completion notifications"
			})
			#expect(timing.dispatchConfiguredAction())
			let menu = try #require(window.childWindows?.first?.contentView)
			#expect(menuTitles(menu) == ["Never", "Only when unfocused", "Always"])
			let never = try #require(descendants(menu).compactMap
			{
				$0 as? NSButton
			}.first
			{
				$0.title == "Never"
			})
			#expect(never.dispatchConfiguredAction())
			#expect(preferences.completionMode == .never)
			let sound = try #require(pickers.first
			{
				$0.accessibilityLabel() == "Notification sound"
			})
			#expect(sound.dispatchConfiguredAction())
			let sounds = try #require(window.childWindows?.first?.contentView)
			#expect(menuTitles(sounds) == ["Default",
											"Classic",
											"None",
											"Basso",
											"Glass",
											"Ping",
											"Pop",
											"Purr",
											"Tink",
											"Choose custom sound…"])
			try snapshot(
				sounds,
				suffix: "sound-menu"
			)
		}
	}

	private func menuTitles(_ view: NSView) -> [String]
	{
		descendants(view).compactMap
		{
			$0 as? NSButton
		}.map(\.title)
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap(descendants)
	}

	private func snapshot(
		_ view: NSView,
		suffix: String
	) throws
	{
		if let directory = ProcessInfo.processInfo.environment["CODEX_GUI_NOTIFICATION_PREVIEW"]
		{
			view.window?.layoutIfNeeded()
			view.layoutSubtreeIfNeeded()
			for child in descendants(view)
			{
				child.needsDisplay = true
			}
			view.display()
			try AppTestPNGWriter.write(
				view,
				to: URL(fileURLWithPath: directory + "/" + suffix + ".png")
			)
		}
	}
}
