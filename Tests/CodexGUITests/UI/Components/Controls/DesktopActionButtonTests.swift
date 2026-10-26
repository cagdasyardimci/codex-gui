import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct DesktopActionButtonTests
{
	@Test func nativeActionUsesCurrentClosureAndCanBeCleared() throws
	{
		_ = NSApplication.shared
		var actions: [String] = []
		let button = DesktopActionButton(
			title: "Save",
			presentation: .secondary
		)
		{
			actions.append("original")
		}
		#expect(button.dispatchConfiguredAction())
		button.onAction =
		{
			actions.append("replacement")
		}
		#expect(button.dispatchConfiguredAction())
		button.onAction = nil
		#expect(button.dispatchConfiguredAction())
		#expect(actions == ["original", "replacement"])
	}

}
