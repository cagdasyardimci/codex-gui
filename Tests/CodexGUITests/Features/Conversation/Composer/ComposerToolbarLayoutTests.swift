import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct ComposerToolbarLayoutTests
{
	@Test(arguments: [CGFloat(360), 440, 720])
	func initialFittingHeightSupportsFirstLayout(width: CGFloat)
	{
		_ = NSApplication.shared
		let leadingButton = NSButton()
		let preferenceButton = ModelEffortSelectionButton()
		let actionButton = NSButton()
		leadingButton.heightAnchor.constraint(equalToConstant: 24).isActive = true
		preferenceButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
		actionButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
		let leading = AppKitLayout.horizontalStack([leadingButton])
		let actions = AppKitLayout.horizontalStack([actionButton])
		let toolbar = ComposerToolbarView(
			leadingControls: leading,
			preferenceControl: preferenceButton,
			actionControls: actions
		)
		let initialHeight = toolbar.fittingSize.height
		toolbar.frame = NSRect(
			x: 0,
			y: 0,
			width: width,
			height: initialHeight
		)
		toolbar.layoutSubtreeIfNeeded()

		#expect(toolbar.fittingSize.height <= initialHeight)
		#expect(leadingButton.frame.height == 24)
		#expect(preferenceButton.frame.height == 28)
		#expect(actionButton.frame.height == 28)
		if width < 440
		{
			#expect(initialHeight >= 56)
			#expect(leading.frame.minY >= actions.frame.maxY + 4)
		}
	}
}
