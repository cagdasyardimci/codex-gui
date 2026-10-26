import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct SettingsPageNavigationTests
{
	@Test(.appKitIsolation)
	func accountUsageNavigationClearsFilteringAndSelectsUsage() throws
	{
		_ = NSApplication.shared
		let controller = SettingsViewController()
		defer
		{
			controller.endPresentation()
		}
		let search = try #require(descendants(controller.view).compactMap
		{
			$0 as? NSSearchField
		}.first)
		let usage = try #require(sidebarButton(
			"Usage & billing",
			in: controller.view
		))
		search.stringValue = "sandbox"
		controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
		#expect(usage.isHidden)

		controller.showUsage()

		#expect(search.stringValue.isEmpty)
		#expect(!usage.isHidden)
		#expect(usage.isSelected)
		#expect(descendants(controller.view).contains
		{
			$0 is SettingsUsagePage
		})
	}

	@Test(.appKitIsolation)
	func searchFindsControlTermsAndKeepsSelectedPageWhenCleared() throws
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
		window.contentView = controller.view
		defer
		{
			controller.endPresentation()
			window.close()
		}
		window.layoutIfNeeded()
		let search = try #require(descendants(controller.view).compactMap
		{
			$0 as? NSSearchField
		}.first)
		search.stringValue = "sandbox"
		controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
		let configuration = try #require(sidebarButton(
			"Configuration",
			in: controller.view
		))
		#expect(!configuration.isHidden)
		let personalHeading = try #require(descendants(controller.view).compactMap
		{
			$0 as? NSTextField
		}.first
		{
			$0.stringValue == "Personal"
		})
		let codingHeading = try #require(descendants(controller.view).compactMap
		{
			$0 as? NSTextField
		}.first
		{
			$0.stringValue == "Coding"
		})
		#expect(!personalHeading.isHiddenOrHasHiddenAncestor)
		#expect(codingHeading.isHiddenOrHasHiddenAncestor)
		#expect(sidebarButton(
			"Plugins",
			in: controller.view
		)?.isHidden == true)
		#expect(configuration.dispatchConfiguredAction())
		let approval = try #require(descendants(controller.view).compactMap
		{
			$0 as? SettingsChoicePicker
		}.first
		{
			$0.accessibilityLabel() == "Approval policy"
		})
		#expect(!approval.isEnabled)
		search.stringValue = ""
		controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
		#expect(sidebarButton(
			"Plugins",
			in: controller.view
		)?.isHidden == false)
		#expect(configuration.isSelected)
		let sectionStack = try #require(configuration.superview as? NSStackView)
		let personalIndex = try #require(sectionStack.arrangedSubviews.firstIndex
		{
			$0 === personalHeading.superview
		})
		let configurationIndex = try #require(sectionStack.arrangedSubviews.firstIndex
		{
			$0 === configuration
		})
		let codingIndex = try #require(sectionStack.arrangedSubviews.firstIndex
		{
			$0 === codingHeading.superview
		})
		#expect(personalIndex < configurationIndex && configurationIndex < codingIndex)
		#expect(approval.window === window)
		#expect(sidebarButton(
			"Browser",
			in: controller.view
		)?.dispatchConfiguredAction() == true)
		#expect(descendants(controller.view).contains
		{
			$0.accessibilityLabel() == "Browser history access"
		})
	}

	@Test(.appKitIsolation)
	func newPagesRemainInsideSettingsAndSidebarScrollsInShortWindow() throws
	{
		_ = NSApplication.shared
		let controller = SettingsViewController()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 1000,
				height: 480
			),
			styleMask: [.titled, .closable, .resizable],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		window.contentView = controller.view
		defer
		{
			controller.endPresentation()
			window.close()
		}
		window.layoutIfNeeded()
		let connections = try #require(sidebarButton(
			"Connections",
			in: controller.view
		))
		let scroll = try #require(connections.enclosingScrollView)
		let document = try #require(scroll.documentView)
		#expect(document.bounds.height > scroll.contentView.bounds.height)
		#expect(sidebarButton(
			"Computer use",
			in: controller.view
		) == nil)
		for title in ["Configuration",
						"Personalization",
						"Browser",
						"Plugins",
						"Hooks",
						"Archived chats",
						"Usage & billing",
						"Voice"]
		{
			let button = try #require(sidebarButton(
				title,
				in: controller.view
			))
			#expect(button.dispatchConfiguredAction())
			window.layoutIfNeeded()
			controller.view.layoutSubtreeIfNeeded()
			#expect(button.isSelected)
			if let path = ProcessInfo.processInfo.environment["CODEX_GUI_SETTINGS_PREVIEW"]
			{
				try AppTestPNGWriter.write(
					controller.view,
					to: URL(fileURLWithPath: path + "." + title + ".png")
				)
			}
			#expect(descendants(controller.view).compactMap
			{
				$0 as? NSTextField
			}.contains
			{
				$0.stringValue == title && $0.font?.pointSize == 28
			})
		}
		let configuration = try #require(sidebarButton(
			"Configuration",
			in: controller.view
		))
		#expect(configuration.dispatchConfiguredAction())
		window.layoutIfNeeded()
		controller.view.layoutSubtreeIfNeeded()
		if let path = ProcessInfo.processInfo.environment["CODEX_GUI_SETTINGS_PREVIEW"]
		{
			try AppTestPNGWriter.write(
				controller.view,
				to: URL(fileURLWithPath: path)
			)
		}
	}

	@Test func appStatusGroupsRouteTheirActionsThroughSharedStatusViews() throws
	{
		_ = NSApplication.shared
		let controller = SettingsViewController()
		defer
		{
			controller.endPresentation()
		}
		var actions: [String] = []
		controller.onLogin =
		{
			actions.append("login")
		}
		controller.onReconnect =
		{
			actions.append("reconnect")
		}
		controller.onShowBackendDetails =
		{
			actions.append("details")
		}
		let statusViews = descendants(controller.view).compactMap
		{
			$0 as? DesktopStatusView
		}
		let account = try #require(statusViews.first
		{
			$0.messageLabel.accessibilityLabel() == "Account status"
		})
		let signIn = try #require(descendants(account).compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.title == "Sign In…"
		})
		#expect(signIn.dispatchConfiguredAction())
		for title in ["Reconnect", "Details"]
		{
			let action = try #require(statusViews.flatMap(descendants).compactMap
			{
				$0 as? NSButton
			}.first
			{
				$0.title == title
			})
			#expect(action.dispatchConfiguredAction())
		}
		#expect(actions == ["login", "reconnect", "details"])
	}

	private func sidebarButton(
		_ title: String,
		in view: NSView
	) -> SettingsSidebarButton?
	{
		descendants(view).compactMap
		{
			$0 as? SettingsSidebarButton
		}.first
		{
			$0.title == title
		}
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap(descendants)
	}
}
