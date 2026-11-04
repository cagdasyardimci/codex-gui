import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct DesktopLineBoxLabelTests
{
	@Test func intrinsicWidthRecoversAfterAConstrainedLayout()
	{
		_ = NSApplication.shared
		let label = DesktopLineBoxLabel(
			"Visual style",
			role: TypographyTokens.Connections.section
		)
		let natural = label.intrinsicContentSize
		label.frame.size = NSSize(
			width: natural.width / 2,
			height: natural.height
		)
		#expect(label.intrinsicContentSize.width == natural.width)
		#expect(label.intrinsicContentSize.height > natural.height)
		label.frame.size = natural
		#expect(label.measuredSize(maximumWidth: natural.width).height == natural.height)
		label.stringValue = "A longer section heading"
		#expect(label.intrinsicContentSize.width > natural.width)
	}
}
