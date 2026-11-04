import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct DesktopNativeButtonTests
{
	@Test func reconfigurationPreservesActionSelectionShortcutAndCell()
	{
		_ = NSApplication.shared
		var calls = 0
		let button = DesktopActionButton(
			title: "Pin",
			presentation: .quiet
		)
		{
			calls += 1
		}
		let cell = button.cell
		button.setButtonType(.toggle)
		button.state = .on
		button.symbol = .pin
		button.keyEquivalent = "p"
		button.keyEquivalentModifierMask = [.command]
		for presentation: DesktopStyledButton.Presentation in [.sidebarIcon, .primary, .quiet]
		{
			button.presentation = presentation
			button.size = .regular
			#expect(button.cell === cell)
			#expect(button.state == .on)
			#expect(button.keyEquivalent == "p")
			#expect(button.keyEquivalentModifierMask == [.command])
			#expect(button.dispatchConfiguredAction())
		}
		#expect(calls == 3)
		button.isEnabled = false
		// Exercise the actual dispatch boundary, not the test helper's enabled guard.
		#expect(!button.sendAction(
			button.action,
			to: button.target
		))
		button.invokeAction()
		#expect(calls == 3)
	}

	@Test func defaultActionsShareAppTypographyAndIncludeLeadingIcons() throws
	{
		_ = NSApplication.shared
		let button = DesktopStyledButton(
			title: "Open",
			target: nil,
			action: nil
		)
		#expect(button.presentation == .quiet)
		let plainWidth = button.intrinsicContentSize.width
		button.symbol = .folder
		#expect(button.intrinsicContentSize.width == plainWidth + 22)
		button.frame.size = button.intrinsicContentSize
		let slots = button.contentLayout(in: button.bounds)
		let icon = try #require(slots.image)
		#expect(icon.width == 16 && icon.height == 16)
		#expect(icon.maxX < slots.title.minX)
		#expect(button.bounds.contains(slots.title))
		button.font = .systemFont(
			ofSize: 40,
			weight: .bold
		)
		#expect(button.font == AppKitFontResolver.font(TypographyTokens.Button.compact))
		button.size = .regular
		#expect(button.font == AppKitFontResolver.font(TypographyTokens.Button.regular))
		button.symbol = nil
		#expect(button.contentLayout(in: button.bounds).image == nil)
	}

	@Test func constrainedTextReservesProgressIconAndMenuSlots() throws
	{
		_ = NSApplication.shared
		let button = DesktopStyledButton(
			title: "A long selected model name",
			presentation: .menuTrigger
		)
		button.symbol = .folder
		button.isLoading = true
		let bounds = NSRect(
			x: 0,
			y: 0,
			width: 120,
			height: 32
		)
		let slots = button.contentLayout(in: bounds)
		let progress = try #require(slots.progress)
		let icon = try #require(slots.image)
		let chevron = try #require(slots.chevron)
		#expect(progress.maxX <= icon.minX)
		#expect(icon.maxX < slots.title.minX)
		#expect(slots.title.maxX < chevron.minX)
		for rect in [progress, icon, slots.title, chevron]
		{
			#expect(bounds.contains(rect))
		}
		#expect(slots.title.width < (button.title as NSString)
			.size(withAttributes: [.font: try #require(button.font)]).width)
	}

	@Test func sidebarRolesUseSharedPresentationAndState()
	{
		_ = NSApplication.shared
		let search = SidebarIconButton(role: .search)
		#expect(search.presentation == .searchIcon)
		#expect(search.intrinsicContentSize == NSSize(
			width: 28,
			height: 28
		))
		for role: SidebarIconButton.Role in [
			.options,
			.add,
			.refresh,
			.projectInfo,
			.projectNewChat
		]
		{
			let button = SidebarIconButton(role: role)
			#expect(button.presentation == .sidebarIcon)
			#expect(button.imagePosition == .imageOnly)
			#expect(button.image != nil)
		}
		search.isSearchActive = true
		#expect(search.state == .on)
		search.isSearchActive = false
		#expect(search.state == .off)
	}
}
