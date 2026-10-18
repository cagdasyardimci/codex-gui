import AppKit
import Testing

@testable import CodexGUI

struct ViewerFileSearchSelectionTests
{
	@Test func fieldCommandsAndTableKeysHaveTheSameSelectionMeaning()
	{
		let commands: [(Selector, UInt16, ViewerFileSearchSelection.Command)] = [
			(#selector(NSResponder.moveUp(_:)), 126, .navigate(.up)),
			(#selector(NSResponder.moveDown(_:)), 125, .navigate(.down)),
			(#selector(NSResponder.moveToBeginningOfDocument(_:)), 115, .navigate(.first)),
			(#selector(NSResponder.moveToEndOfDocument(_:)), 119, .navigate(.last)),
			(#selector(NSResponder.insertNewline(_:)), 36, .accept),
			(#selector(NSResponder.cancelOperation(_:)), 53, .cancel),
		]
		for (selector, keyCode, command) in commands
		{
			#expect(ViewerFileSearchSelection.command(for: selector) == command)
			#expect(ViewerFileSearchSelection.command(forKeyCode: keyCode) == command)
		}
		#expect(ViewerFileSearchSelection.command(
			for: #selector(NSResponder.moveToBeginningOfLine(_:))
		) == .navigate(.first))
		#expect(ViewerFileSearchSelection.command(
			for: #selector(NSResponder.moveToEndOfLine(_:))
		) == .navigate(.last))
		#expect(ViewerFileSearchSelection.command(forKeyCode: 76) == .accept)
		#expect(ViewerFileSearchSelection.command(forKeyCode: 0) == nil)
	}
}
