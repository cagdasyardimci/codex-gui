import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct SettingsChoiceMenuTests
{
	@Test func multipleSelectionKeepsChecksIndependentOfNavigationAndStaysOpen() async throws
	{
		try await AppKitTestIsolation.perform
		{
			_ = NSApplication.shared
			let window = NSWindow(
				contentRect: NSRect(
					x: 100,
					y: 100,
					width: 400,
					height: 300
				),
				styleMask: [.borderless],
				backing: .buffered,
				defer: false
			)
			window.prepareForTesting()
			let anchor = NSButton(frame: NSRect(
				x: 100,
				y: 180,
				width: 140,
				height: 28
			))
			window.contentView?.addSubview(anchor)
			let menu = SettingsChoiceMenu(
				choices: [
					.init(
						id: "low",
						title: "Light"
					),
					.init(
						id: "high",
						title: "High"
					),
				],
				selectedID: nil,
				accessibilityLabel: "Efforts",
				checkedIDs: ["high"]
			)
			defer
			{
				menu.close(); window.close()
			}
			window.orderFront(nil)
			menu.show(from: anchor)
			let panel = try #require(window.childWindows?.first)
			var toggled: [String] = []
			menu.onToggle =
			{
				id, _ in toggled.append(id)
			}
			#expect(menu.isShown)
			#expect(menu.checkedIDs == ["high"])
			NSApp.sendEvent(try key(
				125,
				window: panel
			))
			#expect(menu.checkedIDs == ["high"])
			NSApp.sendEvent(try key(
				49,
				window: panel
			))
			#expect(menu.isShown)
			#expect(menu.checkedIDs == [])
			#expect(toggled == ["high"])
			menu.updateChecks(["low"])
			#expect(menu.isShown)
			NSApp.sendEvent(try key(
				49,
				window: panel
			))
			#expect(menu.checkedIDs == ["low", "high"])
			#expect(toggled == ["high", "high"])
			NSApp.sendEvent(try key(
				53,
				window: panel
			))
			#expect(!menu.isShown)
		}
	}

	@Test func groupedMenusKeepIndependentChecksAndSkipDisabledItems() async throws
	{
		try await AppKitTestIsolation.perform
		{
			_ = NSApplication.shared
			let window = NSWindow(
				contentRect: NSRect(
					x: 100,
					y: 100,
					width: 400,
					height: 400
				),
				styleMask: [.borderless],
				backing: .buffered,
				defer: false
			)
			window.prepareForTesting()
			let anchor = NSButton(frame: NSRect(
				x: 100,
				y: 250,
				width: 140,
				height: 28
			))
			window.contentView?.addSubview(anchor)
			let menu = SettingsChoiceMenu(
				choices: [
					.init(
						id: "all",
						title: "All chats",
						section: "Type",
						isSelected: true
					),
					.init(
						id: "cloud",
						title: "Cloud",
						isEnabled: false,
						help: "Cloud archives are unavailable."
					),
					.init(
						id: "local",
						title: "Local",
						isSelected: false
					),
					.init(
						id: "updated",
						title: "Last updated",
						section: "Sort",
						isSelected: true
					),
				],
				selectedID: "all",
				accessibilityLabel: "Archive filters",
				width: 208
			)
			defer
			{
				menu.close(); window.close()
			}
			window.orderFront(nil)
			menu.show(from: anchor)
			let panel = try #require(window.childWindows?.first)
			let content = try #require(panel.contentView)
			let buttons = descendants(in: content).compactMap
			{
				$0 as? NSButton
			}
			#expect(buttons.count == 4)
			#expect(buttons.filter
			{
				$0.state == .on
			}.map(\.title) == [
				"All chats",
				"Last updated"
			])
			let headers = descendants(in: content).compactMap
			{
				$0 as? NSTextField
			}.filter
			{
				$0.identifier?.rawValue == "settings-menu-section-heading"
			}
			#expect(headers.map(\.stringValue) == ["Type", "Sort"])
			let cloud = try #require(buttons.first
			{
				$0.title == "Cloud"
			})
			#expect(!cloud.isEnabled)
			#expect(cloud.toolTip == "Cloud archives are unavailable.")
			var selected: String?
			menu.onSelect =
			{
				selected = $0
			}
			_ = cloud.dispatchConfiguredAction()
			#expect(selected == nil)
			#expect(menu.isShown)
			NSApp.sendEvent(try key(
				125,
				window: panel
			))
			#expect((panel.firstResponder as? NSButton)?.title == "Local")
			#expect(buttons.filter
			{
				$0.state == .on
			}.count == 2)
			NSApp.sendEvent(try key(
				36,
				window: panel
			))
			#expect(selected == "local")
			#expect(!menu.isShown)
		}
	}

	@Test func longMenuCapsItsSurfaceAndScrollsKeyboardSelectionIntoView() async throws
	{
		try await AppKitTestIsolation.perform
		{
			_ = NSApplication.shared
			let window = NSWindow(
				contentRect: NSRect(
					x: 100,
					y: 100,
					width: 500,
					height: 500
				),
				styleMask: [.borderless],
				backing: .buffered,
				defer: false
			)
			window.prepareForTesting()
			let anchor = NSButton(frame: NSRect(
				x: 100,
				y: 250,
				width: 140,
				height: 28
			))
			window.contentView?.addSubview(anchor)
			let menu = SettingsChoiceMenu(
				choices: (0 ..< 40).map
				{
					.init(
						id: "\($0)",
						title: "Project \($0)"
					)
				},
				selectedID: "0",
				accessibilityLabel: "Projects",
				width: 260
			)
			defer
			{
				menu.close(); window.close()
			}
			window.orderFront(nil)
			menu.show(from: anchor)
			let panel = try #require(window.childWindows?.first)
			#expect(panel.frame.height <= 350 + 48)
			let content = try #require(panel.contentView)
			let scroll = try #require(descendants(in: content).compactMap
			{
				$0 as? NSScrollView
			}
			.first)
			let document = try #require(scroll.documentView)
			#expect(document.bounds.height > scroll.contentView.bounds.height)
			for _ in 0 ..< 35
			{
				NSApp.sendEvent(try key(
					125,
					window: panel
				))
			}
			let row = try #require(panel.firstResponder as? NSButton)
			#expect(row.title == "Project 35")
			#expect(scroll.contentView.bounds.minY > 0)
			let rect = document.convert(
				row.bounds,
				from: row
			)
			#expect(document.visibleRect.contains(rect))
			NSApp.sendEvent(try key(
				53,
				window: panel
			))
			#expect(!menu.isShown)
		}
	}

	@Test func editorPickerOpensA220PointMenu() async throws
	{
		try await AppKitTestIsolation.perform
		{
			_ = NSApplication.shared
			let window = NSWindow(
				contentRect: NSRect(
					x: 100,
					y: 100,
					width: 400,
					height: 300
				),
				styleMask: [.borderless],
				backing: .buffered,
				defer: false
			)
			window.prepareForTesting()
			let picker = SettingsEditorPicker()
			picker.frame = NSRect(
				x: 100,
				y: 180,
				width: 140,
				height: 28
			)
			window.contentView?.addSubview(picker)
			defer
			{
				picker.removeFromSuperview(); window.close()
			}
			window.orderFront(nil)
			#expect(picker.dispatchConfiguredAction())
			let panel = try #require(window.childWindows?.first)
			let content = try #require(panel.contentView)
			let surface = try #require(descendants(in: content).first
			{
				$0 is DesktopPopoverSurface
			})
			#expect(surface.frame.width == 220)
		}
	}

	@Test func menuRestoresAfterParentMiniaturization() async throws
	{
		try await AppKitTestIsolation.perform
		{
			_ = NSApplication.shared
			let window = NSWindow(
				contentRect: NSRect(
					x: 100,
					y: 100,
					width: 400,
					height: 300
				),
				styleMask: [.borderless],
				backing: .buffered,
				defer: false
			)
			window.prepareForTesting()
			let anchor = NSButton(frame: NSRect(
				x: 100,
				y: 180,
				width: 140,
				height: 28
			))
			window.contentView?.addSubview(anchor)
			let menu = SettingsChoiceMenu(
				choices: [.init(
					id: "default",
					title: "Default app"
				)],
				selectedID: "default",
				accessibilityLabel: "Editor choices"
			)
			defer
			{
				menu.close(); window.close()
			}
			window.orderFront(nil)
			menu.show(from: anchor)
			let panel = try #require(window.childWindows?.first)
			NotificationCenter.default.post(
				name: NSWindow.willMiniaturizeNotification,
				object: window
			)
			NotificationCenter.default.post(
				name: NSApplication.didResignActiveNotification,
				object: NSApp
			)
			#expect(menu.isShown)
			NotificationCenter.default.post(
				name: NSWindow.didMiniaturizeNotification,
				object: window
			)
			#expect(menu.isShown)
			panel.orderOut(nil)
			#expect(!panel.isVisible)
			NotificationCenter.default.post(
				name: NSWindow.didDeminiaturizeNotification,
				object: window
			)
			#expect(menu.isShown)
			#expect(panel.isVisible)
			#expect(window.childWindows?.contains(panel) == true)
			NotificationCenter.default.post(
				name: NSApplication.didResignActiveNotification,
				object: NSApp
			)
			#expect(!menu.isShown)
		}
	}

	@Test func trailingMultiSelectKeepsRequiredEffortsAndTogglesOptionalEffortsIndependently(
	) async throws
	{
		try await AppKitTestIsolation.perform
		{
			_ = NSApplication.shared
			let window = NSWindow(
				contentRect: NSRect(
					x: 100,
					y: 100,
					width: 400,
					height: 400
				),
				styleMask: [.borderless],
				backing: .buffered,
				defer: false
			)
			window.prepareForTesting()
			window.appearance = NSAppearance(named: .aqua)
			window.contentView = SettingsSurfaceView(color: AppKitColorTokens.canvas)
			let required = Set(["low", "medium", "high", "xhigh"])
			let choices: [SettingsChoicePicker.Choice] = [
				.init(
					id: "low",
					title: "Light",
					isEnabled: false
				),
				.init(
					id: "medium",
					title: "Medium",
					isEnabled: false
				),
				.init(
					id: "high",
					title: "High",
					isEnabled: false
				),
				.init(
					id: "xhigh",
					title: "Extra High",
					isEnabled: false
				),
				.init(
					id: "max",
					title: "Max"
				),
				.init(
					id: "ultra",
					title: "Ultra"
				),
			]
			let picker = SettingsChoicePicker(choices: choices)
			picker.usesCheckboxesForMultipleSelection = false
			var checked = required.union(["max"])
			var toggled: [String] = []
			picker.setMultipleChoices(
				choices,
				checkedIDs: checked,
				title: "5 selected"
			)
			picker.onToggle =
			{
				id, enabled in
				toggled.append(id)
				if enabled
				{
					checked.insert(id)
				}
				else
				{
					checked.remove(id)
				}
				picker.setMultipleChoices(
					choices,
					checkedIDs: checked,
					title: "\(checked.count) selected"
				)
			}
			picker.frame = NSRect(
				x: 100,
				y: 250,
				width: 140,
				height: 28
			)
			window.contentView?.addSubview(picker)
			defer
			{
				picker.removeFromSuperview(); window.close()
			}
			window.orderFront(nil)
			#expect(picker.dispatchConfiguredAction())
			let panel = try #require(window.childWindows?.first)
			let content = try #require(panel.contentView)
			let rows = descendants(in: content).compactMap
			{
				$0 as? NSButton
			}
			#expect(rows.count == 6)
			#expect(rows.allSatisfy
			{
				$0.focusRingType == .none
			})
			#expect((panel.firstResponder as? NSButton)?.title == "Max")
			for row in rows.prefix(4)
			{
				#expect(!row.isEnabled)
				#expect(row.state == .on)
				#expect(!row.dispatchConfiguredAction())
			}
			NSApp.sendEvent(try key(
				49,
				window: panel
			))
			#expect(checked == required)
			#expect(panel.isVisible)
			NSApp.sendEvent(try key(
				125,
				window: panel
			))
			#expect((panel.firstResponder as? NSButton)?.title == "Ultra")
			NSApp.sendEvent(try key(
				49,
				window: panel
			))
			#expect(checked == required.union(["ultra"]))
			NSApp.sendEvent(try key(
				126,
				window: panel
			))
			#expect((panel.firstResponder as? NSButton)?.title == "Max")
			NSApp.sendEvent(try key(
				49,
				window: panel
			))
			#expect(checked == required.union(["max", "ultra"]))
			#expect(toggled == ["max", "ultra", "max"])
			#expect(panel.isVisible)
			NSApp.sendEvent(try key(
				126,
				window: panel
			))
			#expect((panel.firstResponder as? NSButton)?.title == "Ultra")
			try captureEffortMenu(content)
			NSApp.sendEvent(try key(
				53,
				window: panel
			))
			#expect(!panel.isVisible)
		}
	}

	private func captureEffortMenu(_ content: NSView) throws
	{
		guard let directory = ProcessInfo.processInfo.environment["CODEX_GUI_EFFORT_PREVIEW"]
		else
		{
			return
		}
		let output = URL(
			fileURLWithPath: directory,
			isDirectory: true
		)
		try FileManager.default.createDirectory(
			at: output,
			withIntermediateDirectories: true
		)
		let background = SettingsSurfaceView(color: AppKitColorTokens.canvas)
		background.frame = content.bounds
		content.addSubview(
			background,
			positioned: .below,
			relativeTo: content.subviews.first
		)
		defer
		{
			background.removeFromSuperview()
		}
		content.window?.layoutIfNeeded()
		content.layoutSubtreeIfNeeded()
		for child in descendants(in: content)
		{
			child.needsDisplay = true
		}
		content.display()
		try AppTestPNGWriter.write(
			content,
			to: output.appendingPathComponent("effort-menu.png")
		)
	}

	private func descendants(in view: NSView) -> [NSView]
	{
		view.subviews.flatMap
		{
			[$0] + descendants(in: $0)
		}
	}

	private func key(
		_ code: UInt16,
		window: NSWindow
	) throws -> NSEvent
	{
		try #require(NSEvent.keyEvent(
			with: .keyDown,
			location: .zero,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: window.windowNumber,
			context: nil,
			characters: "",
			charactersIgnoringModifiers: "",
			isARepeat: false,
			keyCode: code
		))
	}
}
