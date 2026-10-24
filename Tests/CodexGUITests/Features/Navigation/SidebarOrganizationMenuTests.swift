import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct SidebarOrganizationMenuTests
{
	@Test func customMenuUsesReferenceGeometryAndKeyboardSelection() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let window = NSWindow(
				contentRect: NSRect(
					x: 200,
					y: 200,
					width: 600,
					height: 300
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			window.isReleasedWhenClosed = false
			let anchor = NSButton(frame: NSRect(
				x: 20,
				y: 200,
				width: 26,
				height: 26
			))
			window.contentView?.addSubview(anchor)
			window.makeKeyAndOrderFront(nil)
			let menu = SidebarOrganizationMenu()
			defer
			{
				menu.close()
				window.close()
			}
			for name: NSAppearance.Name in [.aqua, .darkAqua, .aqua]
			{
				window.appearance = NSAppearance(named: name)
				menu.show(
					from: anchor,
					organization: .byProject,
					sortOrder: .lastUpdated
				)
				#expect(menu.mainRows.map(\.title) == ["Organize sidebar", "Sort chats by"])
				#expect(menu.mainRows[0].frame.width == 212)
				#expect(menu.mainRows[0].frame.height == 28.5703125)
				menu.openSubmenu(
					0,
					focusOptions: false
				)
				#expect(menu.optionRows.map(\.title) == ["By project", "In one list"])
				#expect(menu.optionRows[0].state == .on)
				#expect(menu.optionRows[0].frame.width == 172)
				#expect(menu.optionRows[0].frame.minY > menu.optionRows[1].frame.minY)
				menu.openSubmenu(
					1,
					focusOptions: false
				)
				#expect(menu.optionRows.map(\.title) == ["Last updated", "Manual order"])
				#expect(menu.optionRows[0].state == .on)
				var selected: SidebarPreferences.SortOrder?
				menu.onSelectSortOrder =
				{
					selected = $0
				}
				// Use the actual application's event route to the panel's local keyboard monitor.
				let panel = try #require(menu.mainRows.first?.window)
				for code: UInt16 in [124, 125, 36]
				{
					let event = try #require(NSEvent.keyEvent(
						with: .keyDown,
						location: .zero,
						modifierFlags: [],
						timestamp: 0,
						windowNumber: panel.windowNumber,
						context: nil,
						characters: "",
						charactersIgnoringModifiers: "",
						isARepeat: false,
						keyCode: code
					))
					NSApp.sendEvent(event)
				}
				#expect(selected == .manual)
				#expect(!menu.isShown)
			}
			menu.show(
				from: anchor,
				organization: .oneList,
				sortOrder: .manual
			)
			menu.openSubmenu(
				0,
				focusOptions: true
			)
			#expect(menu.optionRows[1].state == .on)
			#expect(menu.handleKey(53))
			#expect(!menu.isShown)
		}
	}

	@Test func anchorClickTogglesMenuAndSearchDismissesIt() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let fixture = try IsolatedUserDefaultsFixture(prefix: "SidebarMenuDismissal")
			defer
			{
				fixture.cleanup()
			}
			let controller = NavigationViewController()
			controller.sidebarPreferences = SidebarPreferences(defaults: fixture.defaults)
			let window = NSWindow(
				contentRect: NSRect(
					x: 200,
					y: 200,
					width: 300,
					height: 500
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			window.isReleasedWhenClosed = false
			window.contentViewController = controller
			window.makeKeyAndOrderFront(nil)
			defer
			{
				controller.searchPopover.close()
				controller.sidebarMenu.close()
				window.close()
			}
			controller.view.layoutSubtreeIfNeeded()
			let anchor = controller.sidebarOptionsButton
			controller.showSidebarMenu(anchor)
			#expect(controller.sidebarMenu.isShown)
			let point = anchor.convert(
				NSPoint(
					x: anchor.bounds.midX,
					y: anchor.bounds.midY
				),
				to: nil
			)
			let click = try #require(NSEvent.mouseEvent(
				with: .leftMouseDown,
				location: point,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 1,
				clickCount: 1,
				pressure: 1
			))
			// The monitor leaves the trigger click for its configured toggle action.
			#expect(controller.sidebarMenu.shouldForward(click))
			#expect(controller.sidebarMenu.isShown)
			controller.showSidebarMenu(anchor)
			#expect(!controller.sidebarMenu.isShown)
			controller.showSidebarMenu(anchor)
			controller.showSearch()
			#expect(!controller.sidebarMenu.isShown)
			#expect(controller.searchPopover.isShown)
		}
	}

	@Test func plusAddsProjectAndFlatListRoutesForeignChatSelection() throws
	{
		let fixture = try IsolatedUserDefaultsFixture(prefix: "SidebarPlus")
		defer
		{
			fixture.cleanup()
		}
		let controller = NavigationViewController()
		controller.sidebarPreferences = SidebarPreferences(defaults: fixture.defaults)
		_ = controller.view
		var opened = 0
		controller.onOpenProject =
		{
			opened += 1
		}
		let plus = controller.projectActionsButton
		#expect(plus.accessibilityLabel() == "Add new project")
		#expect(plus.sendAction(
			try #require(plus.action),
			to: plus.target
		))
		#expect(opened == 1)
		#expect(!controller.projectActionsPopover.isShown)
		controller.setSidebarOrganization(.oneList)
		#expect(plus.accessibilityLabel() == "New chat")
		let foreign = try #require(ThreadSummary(json: ["id": "foreign", "cwd": "/tmp/other"]))
		var selected: String?
		controller.onSelectSidebarTask =
		{
			selected = $0.id
		}
		controller.chooseSidebarThread(foreign)
		#expect(selected == "foreign")
	}
}
