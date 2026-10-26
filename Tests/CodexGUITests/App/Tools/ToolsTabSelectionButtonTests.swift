import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct ToolsTabSelectionButtonTests
{
	@Test func presentationKeepsNativeRoutingAndSelectionThroughCellInstallation()
	{
		_ = NSApplication.shared
		let receiver = Receiver()
		let button = ToolsTabSelectionButton(
			title: "Review",
			target: receiver,
			action: #selector(Receiver.select)
		)
		let image = DesktopIcons.image(.folder)
		button.image = image
		button.state = .on
		button.keyEquivalent = "r"
		button.keyEquivalentModifierMask = [.command, .shift]
		button.tag = 42
		button.configurePresentation(
			selected: true,
			file: true
		)
		let installedCell = button.cell
		#expect(button.target === receiver)
		#expect(button.action == #selector(Receiver.select))
		#expect(button.image === image)
		#expect(button.state == .on)
		#expect(button.keyEquivalent == "r")
		#expect(button.keyEquivalentModifierMask == [.command, .shift])
		#expect(button.tag == 42)
		#expect(button.dispatchConfiguredAction())
		button.configurePresentation(
			selected: false,
			preview: true
		)
		#expect(button.cell === installedCell)
		#expect(button.dispatchConfiguredAction())
		#expect(receiver.selectionCount == 2)
		button.isEnabled = false
		button.configurePresentation(selected: false)
		#expect(!button.dispatchConfiguredAction())
		#expect(receiver.selectionCount == 2)
	}

	@MainActor
	private final class Receiver: NSObject
	{
		var selectionCount = 0
		@objc func select()
		{
			selectionCount += 1
		}
	}
}
